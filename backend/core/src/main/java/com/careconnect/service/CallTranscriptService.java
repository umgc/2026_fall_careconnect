package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.exception.AppException;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.TranscriptArchiveLifecycleRepository;
import com.careconnect.util.ContentHashUtil;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;

/**
 * Service that records, reads, and formats transcript content for calls.
 */
@Service
@RequiredArgsConstructor
public class CallTranscriptService {

    /**
     * Maximum number of transcript segments accepted in one request.
     */
    private static final int MAX_REQUEST_SEGMENTS = 200;

    /**
     * Maximum characters retained from an individual transcript segment.
     */
    private static final int MAX_TEXT_CHARS = 1200;

    /**
     * Maximum characters retained for normalized speaker labels.
     */
    private static final int MAX_LABEL_CHARS = 60;

    /**
     * Maximum characters retained for transcript source labels.
     */
    private static final int MAX_SOURCE_CHARS = 80;

    /**
     * Maximum transcript characters used for summary generation.
     */
    private static final int MAX_SUMMARY_CHARS = 16_000;

    /**
     * Default source label used when none is provided.
     */
    private static final String DEFAULT_SOURCE = "CLIENT_TRANSCRIPT";

    /**
     * Fallback speaker label when no usable value is provided.
     */
    private static final String UNKNOWN_SPEAKER = "UNKNOWN";

    /**
     * Repository used to store and query transcript segments.
     */
    private final CallTranscriptSegmentRepository segmentRepository;

    /**
     * Service used to read and archive transcript payloads.
     */
    private final CallTranscriptArchiveService archiveService;

    /**
     * Emits TRANSCRIPT_INDEXED events after successful segment batches.
     */
    private final IndexingEventEmitter indexingEventEmitter;

    /**
     * Resolves patient ownership from the authoritative call session.
     */
    private final CallPatientResolver callPatientResolver;

    /**
     * Durable terminal-purge fence checked by every transcript writer.
     */
    private final TranscriptArchiveLifecycleRepository lifecycleRepository;

    /**
     * PostgreSQL advisory lock helper used to serialize transcript writes/purges.
     */
    private final DatabaseLockService databaseLockService;

    private static void validateSegmentCount(final List<TranscriptSegmentInput> segments) {
        if (segments.size() > MAX_REQUEST_SEGMENTS) {
            throw new IllegalArgumentException("Too many transcript segments in one request");
        }
    }

    private static String truncateText(final String text) {
        final String truncatedText;
        if (text == null) {
            truncatedText = null;
        } else if (text.length() > MAX_TEXT_CHARS) {
            truncatedText = text.substring(0, MAX_TEXT_CHARS);
        } else {
            truncatedText = text;
        }
        return truncatedText;
    }

    private static Map<String, Long> deletedCounts(
            final long deletedSegments,
            final long deletedArchives) {
        return Map.of(
                "deletedTranscriptSegments", deletedSegments,
                "deletedTranscriptArchives", deletedArchives);
    }

    private static String normalizeSummarySpeaker(final String speakerLabel) {
        final String speaker = trim(speakerLabel);
        return speaker == null ? UNKNOWN_SPEAKER : speaker;
    }

    private static String trim(final String value) {
        final String trimmedValue;
        if (value == null) {
            trimmedValue = null;
        } else {
            final String trimmed = value.trim();
            trimmedValue = trimmed.isEmpty() ? null : trimmed;
        }
        return trimmedValue;
    }

    /**
     * Stores transcript segments for a call and emits a
     * {@code TRANSCRIPT_INDEXED} event to the indexing outbox when at
     * least one segment was persisted. The persist and the emit share
     * one transaction so downstream indexing never sees a segment batch
     * without its notification (or vice versa).
     *
     * @param callId      call identifier
     * @param actorUserId speaking or submitting user identifier
     * @param segments    transcript segments to persist
     * @return number of stored segments
     */
    @Transactional
    public int recordSegments(
            final String callId,
            final Long actorUserId,
            final List<TranscriptSegmentInput> segments) {
        final String normalizedCallId = trim(callId);
        int saved = 0;
        if (normalizedCallId != null && segments != null && !segments.isEmpty()) {
            validateSegmentCount(segments);
            databaseLockService.acquireCallArchiveLock(normalizedCallId);
            lifecycleRepository.ensureActive(normalizedCallId);
            if (lifecycleRepository.find(normalizedCallId).purged()) {
                throw new AppException(HttpStatus.GONE, "Transcript was permanently purged");
            }
            for (final TranscriptSegmentInput input : segments) {
                final String text = truncateText(input == null ? null : trim(input.text()));
                if (text == null) {
                    continue;
                }
                final CallTranscriptSegment segment =
                        createSegment(normalizedCallId, actorUserId, input, text);
                saved += segmentRepository.insertIdempotent(
                        segment.getCallId(),
                        segment.getClientSegmentId(),
                        segment.getSpeakerLabel(),
                        segment.getText(),
                        segment.getStartMs(),
                        segment.getEndMs(),
                        segment.getSource(),
                        segment.getActorUserId(),
                        segment.getOccurredAt());
            }
            if (saved > 0) {
                final Long patientId = callPatientResolver.requirePatientId(normalizedCallId);
                final IndexingSnapshot snapshot = captureIndexingSnapshot(normalizedCallId);
                indexingEventEmitter.emitTranscriptIndexed(new TranscriptIndexedPayload(
                        normalizedCallId,
                        patientId,
                        Math.toIntExact(snapshot.segments().size()),
                        snapshot.version()));
            }
        }
        return saved;
    }

    /**
     * Returns all transcript segments for a call, including archived data.
     *
     * @param callId call identifier
     * @return merged transcript segments in chronological order
     */
    public List<CallTranscriptSegment> getSegmentsForCall(final String callId) {
        final String normalizedCallId = trim(callId);
        final List<CallTranscriptSegment> segments;
        if (normalizedCallId == null) {
            segments = List.of();
        } else {
            final List<CallTranscriptSegment> dbSegments =
                    segmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(normalizedCallId);
            final List<CallTranscriptSegment> archivedSegments =
                    archiveService.getArchivedSegments(normalizedCallId);
            if (archivedSegments.isEmpty()) {
                segments = dbSegments;
            } else if (dbSegments.isEmpty()) {
                segments = archivedSegments;
            } else {
                segments = mergeSegments(archivedSegments, dbSegments);
            }
        }
        return segments;
    }

    /**
     * Returns the total transcript segment count for a call.
     *
     * @param callId call identifier
     * @return transcript segment count
     */
    public long countSegments(final String callId) {
        final String normalizedCallId = trim(callId);
        final long segmentCount;
        if (normalizedCallId == null) {
            segmentCount = 0;
        } else {
            final long dbCount = segmentRepository.countByCallId(normalizedCallId);
            if (dbCount <= 0) {
                segmentCount = archiveService.getArchivedSegmentCount(normalizedCallId);
            } else if (!archiveService.isArchived(normalizedCallId)) {
                segmentCount = dbCount;
            } else {
                segmentCount = getSegmentsForCall(normalizedCallId).size();
            }
        }
        return segmentCount;
    }

    /**
     * Returns whether a user can access transcript content for a call.
     *
     * @param callId call identifier
     * @param userId requesting user identifier
     * @return {@code true} when transcript content is accessible
     */
    public boolean hasTranscriptAccess(final String callId, final Long userId) {
        final String normalizedCallId = trim(callId);
        final boolean hasAccess;
        if (normalizedCallId == null || userId == null) {
            hasAccess = false;
        } else if (segmentRepository.existsByCallIdAndActorUserId(normalizedCallId, userId)) {
            hasAccess = true;
        } else {
            hasAccess = archiveService.hasArchivedTranscriptAccess(normalizedCallId, userId);
        }
        return hasAccess;
    }

    /**
     * Builds a summary-friendly transcript string for a call.
     *
     * @param callId call identifier
     * @return transcript text used for summary generation
     */
    public String buildTranscriptTextForSummary(final String callId) {
        return captureSummarySnapshot(callId).transcriptText();
    }

    /**
     * Captures text, count, and a deterministic version from one materialized segment list.
     * The returned value is detached from later transcript writes and is safe to use during
     * remote inference after this short read transaction completes.
     */
    @Transactional(readOnly = true)
    public TranscriptSnapshot captureSummarySnapshot(final String callId) {
        final String normalizedCallId = trim(callId);
        final List<CallTranscriptSegment> segments =
                normalizedCallId == null
                        ? List.of()
                        : getAuthoritativeSegmentsForCall(normalizedCallId);
        final String transcriptText;
        if (segments.isEmpty()) {
            transcriptText = "";
        } else {
            final StringBuilder out = new StringBuilder();
            for (final CallTranscriptSegment segment : segments) {
                final String text = trim(segment.getText());
                if (text == null) {
                    continue;
                }
                final String speaker = normalizeSummarySpeaker(segment.getSpeakerLabel());
                final String line = String.format("[%s] %s%n", speaker, text);
                if (out.length() + line.length() > MAX_SUMMARY_CHARS) {
                    break;
                }
                out.append(line);
            }
            transcriptText = out.toString().trim();
        }
        final String version = ContentHashUtil.sha256(
                transcriptText + "\nsegmentCount=" + segments.size());
        return new TranscriptSnapshot(transcriptText, segments.size(), version);
    }

    /**
     * Materializes the complete archive-plus-live transcript used by retrieval indexing.
     */
    @Transactional(readOnly = true)
    public IndexingSnapshot captureIndexingSnapshot(final String callId) {
        final String normalizedCallId = trim(callId);
        final List<CallTranscriptSegment> segments =
                normalizedCallId == null
                        ? List.of()
                        : List.copyOf(getAuthoritativeSegmentsForCall(normalizedCallId));
        final StringBuilder versionInput = new StringBuilder();
        for (final CallTranscriptSegment segment : segments) {
            versionInput.append(segmentKey(segment)).append('\n');
        }
        versionInput.append("segmentCount=").append(segments.size());
        return new IndexingSnapshot(
                segments, ContentHashUtil.sha256(versionInput.toString()));
    }

    /**
     * Archives transcript data when the configured thresholds are met.
     *
     * @param callId call identifier
     * @return {@code true} when transcript data was archived
     */
    public boolean archiveIfEligible(final String callId) {
        final String normalizedCallId = trim(callId);
        final boolean archived;
        if (normalizedCallId == null) {
            archived = false;
        } else {
            archived = archiveService.archiveIfEligible(normalizedCallId);
        }
        return archived;
    }

    /**
     * Returns whether transcript data for a call has been archived.
     *
     * @param callId call identifier
     * @return {@code true} when transcript data is archived
     */
    public boolean isArchived(final String callId) {
        return archiveService.isArchived(callId);
    }

    /**
     * Deletes transcript data for a call from both live and archived storage.
     *
     * @param callId call identifier
     * @return counts for the deleted transcript records
     */
    @Transactional
    public Map<String, Long> purgeForCall(final String callId) {
        final String normalizedCallId = trim(callId);
        final Map<String, Long> purgeCounts;
        if (normalizedCallId == null) {
            purgeCounts = deletedCounts(0L, 0L);
        } else {
            final CallTranscriptArchiveService.TranscriptPurgeResult result =
                    archiveService.purgeTranscriptForCall(normalizedCallId);
            purgeCounts = deletedCounts(result.deletedSegments(), result.deletedArchives());
        }
        return purgeCounts;
    }

    private CallTranscriptSegment createSegment(
            final String normalizedCallId,
            final Long actorUserId,
            final TranscriptSegmentInput input,
            final String text) {
        final CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setCallId(normalizedCallId);
        segment.setClientSegmentId(input.clientSegmentId());
        segment.setActorUserId(actorUserId);
        segment.setSpeakerLabel(normalizeSpeaker(input.speakerLabel()));
        segment.setText(text);
        segment.setStartMs(input.startMs());
        segment.setEndMs(input.endMs());
        segment.setSource(normalizeSource(input.source()));
        // The legacy column has no offset; new values are normalized to UTC so index
        // metadata can safely interpret them with ZoneOffset.UTC.
        segment.setOccurredAt(
                input.occurredAt() != null
                        ? input.occurredAt()
                        : LocalDateTime.now(ZoneOffset.UTC));
        return segment;
    }

    private List<CallTranscriptSegment> getAuthoritativeSegmentsForCall(
            final String normalizedCallId) {
        final List<CallTranscriptSegment> dbSegments =
                segmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(normalizedCallId);
        final List<CallTranscriptSegment> archivedSegments =
                archiveService.getArchivedSegments(normalizedCallId);
        if (archiveService.isArchived(normalizedCallId)) {
            final long expectedArchivedCount =
                    archiveService.getArchivedSegmentCount(normalizedCallId);
            if (archivedSegments.size() != expectedArchivedCount) {
                throw new IllegalStateException(
                        "Authoritative transcript archive is unavailable or incomplete for callId="
                                + normalizedCallId);
            }
        }
        if (archivedSegments.isEmpty()) {
            return dbSegments;
        }
        if (dbSegments.isEmpty()) {
            return archivedSegments;
        }
        return mergeSegments(archivedSegments, dbSegments);
    }

    private List<CallTranscriptSegment> mergeSegments(
            final List<CallTranscriptSegment> archivedSegments,
            final List<CallTranscriptSegment> dbSegments) {
        final List<CallTranscriptSegment> merged =
                new ArrayList<>(archivedSegments.size() + dbSegments.size());
        final Set<String> seen = new HashSet<>();

        for (final CallTranscriptSegment segment : archivedSegments) {
            if (segment == null) {
                continue;
            }
            merged.add(segment);
            seen.add(segmentKey(segment));
        }

        for (final CallTranscriptSegment segment : dbSegments) {
            if (segment == null) {
                continue;
            }
            if (seen.add(segmentKey(segment))) {
                merged.add(segment);
            }
        }

        merged.sort(
                Comparator.comparing(
                                CallTranscriptSegment::getStartMs, Comparator.nullsLast(Long::compareTo))
                        .thenComparing(
                                CallTranscriptSegment::getOccurredAt,
                                Comparator.nullsLast(LocalDateTime::compareTo)));
        return merged;
    }

    private String segmentKey(final CallTranscriptSegment segment) {
        return (segment.getSpeakerLabel() == null ? "" : segment.getSpeakerLabel().trim())
                + "|"
                + (segment.getText() == null ? "" : segment.getText().trim())
                + "|"
                + (segment.getStartMs() == null ? "" : segment.getStartMs())
                + "|"
                + (segment.getEndMs() == null ? "" : segment.getEndMs())
                + "|"
                + (segment.getSource() == null ? "" : segment.getSource().trim());
    }

    private String normalizeSpeaker(final String speakerLabel) {
        String normalized = trim(speakerLabel);
        if (normalized == null) {
            normalized = UNKNOWN_SPEAKER;
        } else {
            normalized = normalized.toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9_\\- ]", "");
            if (normalized.isBlank()) {
                normalized = UNKNOWN_SPEAKER;
            } else if (normalized.length() > MAX_LABEL_CHARS) {
                normalized = normalized.substring(0, MAX_LABEL_CHARS);
            }
        }
        return normalized;
    }

    private String normalizeSource(final String source) {
        String normalized = defaultIfBlank(source, DEFAULT_SOURCE);
        normalized = normalized.replaceAll("[^A-Za-z0-9_\\-./ ]", "");
        if (normalized.length() > MAX_SOURCE_CHARS) {
            normalized = normalized.substring(0, MAX_SOURCE_CHARS);
        }
        return normalized;
    }

    private String defaultIfBlank(final String value, final String fallback) {
        final String trimmed = trim(value);
        return trimmed == null ? fallback : trimmed;
    }

    /**
     * Input payload for storing transcript segments.
     * {@code occurredAt} is an offset-free UTC value. When null, the segment is
     * timestamped from the UTC clock.
     */
    public record TranscriptSegmentInput(
            UUID clientSegmentId, String speakerLabel, String text, Long startMs, Long endMs, String source,
            LocalDateTime occurredAt) {

        /**
         * Convenience constructor that leaves occurredAt null (defaults to now on persist).
         */
        public TranscriptSegmentInput(
                UUID clientSegmentId,
                String speakerLabel, String text, Long startMs, Long endMs, String source) {
            this(clientSegmentId, speakerLabel, text, startMs, endMs, source, null);
        }

        /**
         * Compatibility constructor for trusted server-produced segments.
         */
        public TranscriptSegmentInput(
                String speakerLabel, String text, Long startMs, Long endMs, String source,
                LocalDateTime occurredAt) {
            this(null, speakerLabel, text, startMs, endMs, source, occurredAt);
        }

        /**
         * Compatibility constructor for trusted server-produced segments.
         */
        public TranscriptSegmentInput(
                String speakerLabel, String text, Long startMs, Long endMs, String source) {
            this(null, speakerLabel, text, startMs, endMs, source, null);
        }
    }

    /**
     * Immutable transcript input used by one summary generation attempt.
     */
    public record TranscriptSnapshot(String transcriptText, long segmentCount, String version) {
    }

    /**
     * Complete immutable transcript snapshot used by retrieval indexing.
     */
    public record IndexingSnapshot(List<CallTranscriptSegment> segments, String version) {
    }
}