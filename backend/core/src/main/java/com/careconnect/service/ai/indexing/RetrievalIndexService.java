package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * Ingests Ask AI indexing events into {@code retrieval_index_chunk} (Task 4.1).
 *
 * <p>Called by {@link IndexWorker} after outbox events are dequeued. Does not publish
 * SNS/SQS itself — that remains a future transport upgrade. Embeddings are left for Task 4.3;
 * FTS {@code search_vector} is maintained by the existing DB trigger.
 */
@Service
public class RetrievalIndexService {

    private static final Logger log = LoggerFactory.getLogger(RetrievalIndexService.class);

    private final CallSummaryRepository callSummaryRepository;
    private final CallTranscriptSegmentRepository transcriptSegmentRepository;
    private final RetrievalIndexChunkRepository chunkRepository;
    private final SummaryChunker summaryChunker;
    private final TranscriptSegmentChunker transcriptSegmentChunker;
    private final ObjectMapper objectMapper;

    public RetrievalIndexService(
            final CallSummaryRepository callSummaryRepository,
            final CallTranscriptSegmentRepository transcriptSegmentRepository,
            final RetrievalIndexChunkRepository chunkRepository,
            final SummaryChunker summaryChunker,
            final TranscriptSegmentChunker transcriptSegmentChunker,
            final ObjectMapper objectMapper) {
        this.callSummaryRepository = callSummaryRepository;
        this.transcriptSegmentRepository = transcriptSegmentRepository;
        this.chunkRepository = chunkRepository;
        this.summaryChunker = summaryChunker;
        this.transcriptSegmentChunker = transcriptSegmentChunker;
        this.objectMapper = objectMapper;
    }

    /**
     * Indexes a successful call summary. Replaces prior chunks for the same
     * {@code source_record_id} (summary id) only when new drafts are non-empty.
     * Skips when {@code contentHash} matches an existing overview chunk.
     *
     * @return number of chunks written (0 when skipped or nothing to index)
     */
    @Transactional
    public int ingestSummaryCreated(final SummaryCreatedPayload payload) {
        if (payload == null || payload.summaryId() == null) {
            throw new IllegalArgumentException("SUMMARY_CREATED payload requires summaryId");
        }
        if (payload.status() != null && !"SUCCESS".equalsIgnoreCase(payload.status().trim())) {
            log.info("Skipping SUMMARY_CREATED for summaryId={} status={}",
                    payload.summaryId(), payload.status());
            return 0;
        }
        if (isVisitSummary(payload)) {
            log.warn(
                    "Skipping SUMMARY_CREATED for summaryId={} — visit_summaries indexing "
                            + "is not implemented yet (Task 1.4)",
                    payload.summaryId());
            return 0;
        }

        final String sourceRecordId = String.valueOf(payload.summaryId());
        if (payload.contentHash() != null
                && !payload.contentHash().isBlank()
                && hasMatchingContentHash(sourceRecordId, payload.contentHash())) {
            log.info("Skipping SUMMARY_CREATED for summaryId={} — contentHash unchanged",
                    payload.summaryId());
            return 0;
        }

        final CallSummary summary = callSummaryRepository.findById(payload.summaryId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "CallSummary not found for summaryId=" + payload.summaryId()));

        final Long patientId = firstNonNull(payload.patientId(), summary.getPatientId());
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index summaryId=" + payload.summaryId()
                            + " — patientId is required on retrieval_index_chunk");
        }

        final String episodeType = firstNonBlank(payload.episodeType(), "call");
        final String caregiverVisibility = firstNonBlank(
                payload.caregiverVisibility(), summary.getCaregiverVisibility());
        final String contentHash = firstNonBlank(payload.contentHash(), null);
        final String engine = firstNonBlank(
                payload.summarizationEngine(), summary.getSummarizationEngine());

        final List<IndexingChunkDraft> drafts = summaryChunker.chunk(
                episodeType,
                summary.getSummaryJson(),
                contentHash,
                caregiverVisibility,
                engine);

        if (drafts.isEmpty()) {
            log.warn(
                    "SUMMARY_CREATED produced no drafts for summaryId={}; leaving existing chunks unchanged",
                    payload.summaryId());
            return 0;
        }

        chunkRepository.deleteBySourceRecordId(sourceRecordId);
        return persistDrafts(patientId, sourceRecordId, drafts);
    }

    /**
     * Indexes all transcript segments for a call. Uses {@code callId} as
     * {@code source_record_id} so re-delivery replaces the prior segment set.
     * Defers (does not burn attempts) when patientId cannot be resolved.
     *
     * @return number of chunks written
     */
    @Transactional
    public int ingestTranscriptIndexed(final TranscriptIndexedPayload payload) {
        if (payload == null || payload.callId() == null || payload.callId().isBlank()) {
            throw new IllegalArgumentException("TRANSCRIPT_INDEXED payload requires callId");
        }
        final String callId = payload.callId().trim();
        final Long patientId = resolvePatientIdForCall(payload.patientId(), callId);
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index transcript for callId=" + callId
                            + " — patientId is required on retrieval_index_chunk");
        }

        final List<CallTranscriptSegment> segments =
                transcriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(callId);
        final List<IndexingChunkDraft> drafts =
                transcriptSegmentChunker.chunk(callId, payload.source(), segments);

        if (drafts.isEmpty()) {
            log.warn(
                    "TRANSCRIPT_INDEXED produced no drafts for callId={}; leaving existing chunks unchanged",
                    callId);
            return 0;
        }

        chunkRepository.deleteBySourceRecordIdAndRecordType(
                callId, RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
        return persistDrafts(patientId, callId, drafts);
    }

    private int persistDrafts(
            final Long patientId,
            final String sourceRecordId,
            final List<IndexingChunkDraft> drafts) {
        final OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        final List<RetrievalIndexChunk> entities = new ArrayList<>(drafts.size());
        for (final IndexingChunkDraft draft : drafts) {
            if (draft == null || draft.chunkText() == null || draft.chunkText().isBlank()) {
                continue;
            }
            entities.add(RetrievalIndexChunk.builder()
                    .patientId(patientId)
                    .recordType(draft.recordType().name())
                    .sourceRecordId(truncateSourceId(sourceRecordId))
                    .chunkText(draft.chunkText())
                    .chunkMetadata(toJson(draft.metadata()))
                    .consentScope(truncateConsent(draft.consentScope()))
                    .indexedAt(now)
                    .build());
        }
        if (entities.isEmpty()) {
            return 0;
        }
        chunkRepository.saveAll(entities);
        log.info("Indexed {} chunk(s) for sourceRecordId={} patientId={}",
                entities.size(), sourceRecordId, patientId);
        return entities.size();
    }

    private boolean hasMatchingContentHash(final String sourceRecordId, final String contentHash) {
        final List<RetrievalIndexChunk> existing =
                chunkRepository.findBySourceRecordIdAndRecordType(
                        sourceRecordId, RetrievalRecordType.CALL_SUMMARY.name());
        final List<RetrievalIndexChunk> visitExisting =
                chunkRepository.findBySourceRecordIdAndRecordType(
                        sourceRecordId, RetrievalRecordType.VISIT_SUMMARY.name());
        final List<RetrievalIndexChunk> all = new ArrayList<>(existing);
        all.addAll(visitExisting);
        for (final RetrievalIndexChunk chunk : all) {
            if (contentHashEquals(chunk.getChunkMetadata(), contentHash)) {
                return true;
            }
        }
        return false;
    }

    private boolean contentHashEquals(final String chunkMetadataJson, final String contentHash) {
        if (chunkMetadataJson == null || chunkMetadataJson.isBlank() || contentHash == null) {
            return false;
        }
        try {
            final JsonNode meta = objectMapper.readTree(chunkMetadataJson);
            final String stored = meta.path("contentHash").asText(null);
            return contentHash.equals(stored);
        } catch (final Exception ex) {
            log.debug("Unable to parse chunk metadata for contentHash compare: {}", ex.getMessage());
            return false;
        }
    }

    private Long resolvePatientIdForCall(final Long payloadPatientId, final String callId) {
        if (payloadPatientId != null) {
            return payloadPatientId;
        }
        final Optional<CallSummary> latest =
                callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(callId);
        return latest.map(CallSummary::getPatientId).orElse(null);
    }

    private String toJson(final Object metadata) {
        if (metadata == null) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(metadata);
        } catch (final JsonProcessingException ex) {
            throw new IllegalStateException("Failed to serialize chunk metadata", ex);
        }
    }

    private static boolean isVisitSummary(final SummaryCreatedPayload payload) {
        final String sourceTable = payload.sourceTable();
        final String episodeType = payload.episodeType();
        return (sourceTable != null && sourceTable.trim().equalsIgnoreCase("visit_summaries"))
                || (episodeType != null && episodeType.trim().equalsIgnoreCase("visit"));
    }

    private static String truncateSourceId(final String sourceRecordId) {
        if (sourceRecordId == null) {
            return null;
        }
        if (sourceRecordId.length() <= RetrievalIndexSchema.SOURCE_RECORD_ID_MAX_LENGTH) {
            return sourceRecordId;
        }
        return sourceRecordId.substring(0, RetrievalIndexSchema.SOURCE_RECORD_ID_MAX_LENGTH);
    }

    private static String truncateConsent(final String consentScope) {
        if (consentScope == null || consentScope.isBlank()) {
            return null;
        }
        final String trimmed = consentScope.trim().toLowerCase(Locale.ROOT);
        if (trimmed.length() <= RetrievalIndexSchema.CONSENT_SCOPE_MAX_LENGTH) {
            return trimmed;
        }
        return trimmed.substring(0, RetrievalIndexSchema.CONSENT_SCOPE_MAX_LENGTH);
    }

    private static Long firstNonNull(final Long a, final Long b) {
        return a != null ? a : b;
    }

    private static String firstNonBlank(final String a, final String b) {
        if (a != null && !a.isBlank()) {
            return a;
        }
        if (b != null && !b.isBlank()) {
            return b;
        }
        return a;
    }
}
