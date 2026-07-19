package com.careconnect.service;

import com.careconnect.model.CallTranscriptArchive;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.CallTranscriptArchiveRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.security.MessageDigest;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Service that archives transcript payloads and serves archived transcript data. */
@Slf4j
@Service
@RequiredArgsConstructor
public class CallTranscriptArchiveService {

  /** Timestamp pattern used in generated transcript archive keys. */
  private static final DateTimeFormatter KEY_TS = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss");

  /** Repository used to persist transcript archive metadata. */
  private final CallTranscriptArchiveRepository archiveRepository;

  /** Repository used to access live transcript segments. */
  private final CallTranscriptSegmentRepository segmentRepository;

  /** Repository used to align transcript archive keys with recordings. */
  private final CallRecordingRepository recordingRepository;

  /** JSON mapper used for archived transcript payloads. */
  private final ObjectMapper objectMapper;

  /** Optional S3 storage service used for transcript archive content. */
  @Autowired(required = false)
  private S3StorageService s3StorageService;

  /** Whether transcript archiving is enabled. */
  @Value("${app.call.transcript.archive.enabled:true}")
  private boolean archiveEnabled;

  /** Minimum segment count required before archiving is attempted. */
  @Value("${app.call.transcript.archive.min-segments:600}")
  private int minArchiveSegments;

  /** Minimum transcript character count required before archiving. */
  @Value("${app.call.transcript.archive.min-chars:120000}")
  private int minArchiveChars;

  /** Whether live transcript rows should be deleted after archiving. */
  @Value("${app.call.transcript.archive.delete-db-after-archive:true}")
  private boolean deleteDbRows;

  /**
   * Returns whether a transcript has already been archived for a call.
   *
   * @param callId call identifier
   * @return {@code true} when archive metadata exists
   */
  public boolean isArchived(final String callId) {
    final String normalizedCallId = normalize(callId);
    final boolean archived;
    if (normalizedCallId == null) {
      archived = false;
    } else {
      archived = archiveRepository.existsByCallId(normalizedCallId);
    }
    return archived;
  }

  /**
   * Returns whether a user can access the archived transcript for a call.
   *
   * @param callId call identifier
   * @param userId requesting user identifier
   * @return {@code true} when the user appears in the archive metadata
   */
  public boolean hasArchivedTranscriptAccess(final String callId, final Long userId) {
    final String normalizedCallId = normalize(callId);
    final boolean hasAccess;
    if (normalizedCallId == null || userId == null) {
      hasAccess = false;
    } else {
      hasAccess =
          archiveRepository
              .findTopByCallIdOrderByArchivedAtDesc(normalizedCallId)
              .map(archive -> containsParticipant(archive.getParticipantUserIds(), userId))
              .orElse(false);
    }
    return hasAccess;
  }

  /**
   * Returns the archived segment count for a call.
   *
   * @param callId call identifier
   * @return archived segment count
   */
  public long getArchivedSegmentCount(final String callId) {
    final String normalizedCallId = normalize(callId);
    final long archivedSegmentCount;
    if (normalizedCallId == null) {
      archivedSegmentCount = 0;
    } else {
      archivedSegmentCount =
          archiveRepository
              .findTopByCallIdOrderByArchivedAtDesc(normalizedCallId)
              .map(CallTranscriptArchive::getSegmentCount)
              .orElse(0)
              .longValue();
    }
    return archivedSegmentCount;
  }

  /**
   * Loads archived transcript segments for a call when available.
   *
   * @param callId call identifier
   * @return archived transcript segments
   */
  public List<CallTranscriptSegment> getArchivedSegments(final String callId) {
    final String normalizedCallId = normalize(callId);
    final List<CallTranscriptSegment> archivedSegments;
    if (normalizedCallId == null || s3StorageService == null) {
      archivedSegments = List.of();
    } else {
      final Optional<CallTranscriptArchive> latest =
          archiveRepository.findTopByCallIdOrderByArchivedAtDesc(normalizedCallId);
      if (latest.isEmpty()) {
        archivedSegments = List.of();
      } else {
        archivedSegments = loadArchivedSegments(normalizedCallId, latest.get());
      }
    }
    return archivedSegments;
  }

  /**
   * Archives transcript data when the configured thresholds are satisfied.
   *
   * @param callId call identifier
   * @return {@code true} when transcript data was archived
   */
  @Transactional
  public boolean archiveIfEligible(final String callId) {
    return archiveIfEligible(callId, null);
  }

  /**
   * Compatibility overload; segments are recaptured under the per-call lock.
   *
   * @param callId call identifier
   * @param ignoredSegments pre-lock segments, intentionally ignored
   * @return {@code true} when transcript data was archived
   */
  public boolean archiveIfEligible(
      final String callId,
      final List<CallTranscriptSegment> ignoredSegments) {
    final String normalizedCallId = normalize(callId);
    final boolean archived;
    if (normalizedCallId == null || !archiveEnabled || s3StorageService == null) {
      archived = false;
    } else {
      segmentRepository.acquireArchiveLock(normalizedCallId);
      final List<CallTranscriptSegment> capturedSegments =
          segmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(normalizedCallId);
      if (archiveRepository.existsByCallId(normalizedCallId)
          || capturedSegments.isEmpty()) {
        archived = false;
      } else {
        final int transcriptChars = countTranscriptChars(capturedSegments);
        if (capturedSegments.size() < minArchiveSegments
            && transcriptChars < minArchiveChars) {
          archived = false;
        } else {
          archived = archiveTranscript(normalizedCallId, capturedSegments, transcriptChars);
        }
      }
    }
    return archived;
  }

  private List<CallTranscriptSegment> loadArchivedSegments(
      final String normalizedCallId,
      final CallTranscriptArchive archive) {
    List<CallTranscriptSegment> segments = List.of();
    try {
      final byte[] bytes = s3StorageService.download(archive.getStorageKey());
      final List<ArchivedTranscriptSegment> payload =
          objectMapper.readValue(bytes, new TypeReference<List<ArchivedTranscriptSegment>>() {});
      final List<CallTranscriptSegment> loadedSegments = new ArrayList<>(payload.size());
      for (final ArchivedTranscriptSegment item : payload) {
        if (item == null || item.text() == null || item.text().isBlank()) {
          continue;
        }
        loadedSegments.add(toSegment(normalizedCallId, item));
      }
      segments = loadedSegments;
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn(
            "Failed to load archived transcript for callId {}: {}",
            normalizedCallId,
            ex.getMessage());
      }
    }
    return segments;
  }

  private CallTranscriptSegment toSegment(
      final String normalizedCallId,
      final ArchivedTranscriptSegment item) {
    final CallTranscriptSegment segment = new CallTranscriptSegment();
    segment.setCallId(normalizedCallId);
    segment.setSpeakerLabel(item.speakerLabel());
    segment.setText(item.text());
    segment.setStartMs(item.startMs());
    segment.setEndMs(item.endMs());
    segment.setSource(item.source());
    segment.setActorUserId(item.actorUserId());
    segment.setOccurredAt(parseDate(item.occurredAt()));
    return segment;
  }

  private static int countTranscriptChars(final List<CallTranscriptSegment> currentSegments) {
    return currentSegments.stream()
        .map(CallTranscriptSegment::getText)
        .filter(text -> text != null && !text.isBlank())
        .mapToInt(String::length)
        .sum();
  }

  private boolean archiveTranscript(
      final String normalizedCallId,
      final List<CallTranscriptSegment> currentSegments,
      final int transcriptChars) {
    boolean archived = false;
    try {
      final List<ArchivedTranscriptSegment> payload = buildPayload(currentSegments);
      final byte[] bytes = objectMapper.writeValueAsBytes(payload);
      final String storageKey = buildStorageKey(normalizedCallId);
      s3StorageService.upload(storageKey, bytes, "application/json");
      final byte[] persistedBytes = s3StorageService.download(storageKey);
      if (!Arrays.equals(MessageDigest.getInstance("SHA-256").digest(bytes),
          MessageDigest.getInstance("SHA-256").digest(persistedBytes))) {
        throw new IllegalStateException("Transcript archive checksum verification failed");
      }
      archiveRepository.save(
          buildArchive(normalizedCallId, currentSegments, transcriptChars, storageKey, bytes));
      if (deleteDbRows) {
        final List<Long> capturedIds = currentSegments.stream()
            .map(CallTranscriptSegment::getId)
            .filter(java.util.Objects::nonNull)
            .toList();
        if (!capturedIds.isEmpty()) {
          segmentRepository.deleteByCallIdAndIdIn(normalizedCallId, capturedIds);
        }
      }
      logArchiveSuccess(normalizedCallId, currentSegments.size(), transcriptChars);
      archived = true;
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn("Transcript archival failed for callId {}: {}", normalizedCallId, ex.getMessage());
      }
    }
    return archived;
  }

  private static List<ArchivedTranscriptSegment> buildPayload(
      final List<CallTranscriptSegment> currentSegments) {
    return currentSegments.stream()
        .map(
            segment ->
                new ArchivedTranscriptSegment(
                    segment.getSpeakerLabel(),
                    segment.getText(),
                    segment.getStartMs(),
                    segment.getEndMs(),
                    segment.getSource(),
                    segment.getActorUserId(),
                    segment.getOccurredAt() == null ? null : segment.getOccurredAt().toString()))
        .toList();
  }

  private CallTranscriptArchive buildArchive(
      final String normalizedCallId,
      final List<CallTranscriptSegment> currentSegments,
      final int transcriptChars,
      final String storageKey,
      final byte[] bytes) {
    final CallTranscriptArchive archive = new CallTranscriptArchive();
    archive.setCallId(normalizedCallId);
    archive.setStorageProvider("S3");
    archive.setStorageKey(storageKey);
    archive.setSegmentCount(currentSegments.size());
    archive.setTranscriptChars(transcriptChars);
    archive.setParticipantUserIds(buildParticipantUserIds(currentSegments));
    archive.setSha256Checksum(sha256(bytes));
    archive.setArchivedAt(LocalDateTime.now());
    return archive;
  }

  private void logArchiveSuccess(
      final String normalizedCallId,
      final int segmentCount,
      final int transcriptChars) {
    if (log.isInfoEnabled()) {
      log.info(
          "Archived transcript for callId={} segments={} chars={} dbDeleted={} ",
          normalizedCallId,
          segmentCount,
          transcriptChars,
          deleteDbRows);
    }
  }

  private String buildStorageKey(final String callId) {
    final LocalDateTime now = LocalDateTime.now();
    final String safeCallId = callId.replaceAll("[^A-Za-z0-9_\\-]", "_");
    final String fileName =
        "transcript_"
            + KEY_TS.format(now)
            + "_"
            + UUID.randomUUID().toString().substring(0, 8)
            + ".json";

    return recordingRepository
        .findTopByCallIdOrderByStartedAtDesc(callId)
        .map(recording -> recording.getS3Prefix())
        .filter(prefix -> prefix != null && !prefix.isBlank())
        .map(prefix -> prefix + "transcripts/" + fileName)
        .orElseGet(
            () ->
                "recordings/"
                    + safeCallId
                    + "/"
                    + KEY_TS.format(now)
                    + "/transcripts/"
                    + fileName);
  }

  private String buildParticipantUserIds(final List<CallTranscriptSegment> segments) {
    return segments.stream()
        .map(CallTranscriptSegment::getActorUserId)
        .filter(id -> id != null && id > 0)
        .map(String::valueOf)
        .collect(Collectors.toCollection(LinkedHashSet::new))
        .stream()
        .collect(Collectors.joining(","));
  }

  private boolean containsParticipant(final String participantUserIds, final Long userId) {
    boolean containsParticipant = false;
    if (participantUserIds != null && !participantUserIds.isBlank()) {
      final String token = String.valueOf(userId);
      for (final String id : participantUserIds.split(",")) {
        if (token.equals(id.trim())) {
          containsParticipant = true;
          break;
        }
      }
    }
    return containsParticipant;
  }

  private String sha256(final byte[] bytes) {
    String hashedValue = "";
    try {
      final MessageDigest digest = MessageDigest.getInstance("SHA-256");
      final byte[] hash = digest.digest(bytes);
      final StringBuilder out = new StringBuilder(hash.length * 2);
      for (final byte value : hash) {
        out.append(String.format("%02x", value));
      }
      hashedValue = out.toString();
    } catch (Exception ex) {
      hashedValue = "";
    }
    return hashedValue;
  }

  private LocalDateTime parseDate(final String value) {
    LocalDateTime parsedDate = LocalDateTime.now();
    try {
      if (value != null && !value.isBlank()) {
        parsedDate = LocalDateTime.parse(value);
      }
    } catch (Exception ignored) {
      parsedDate = LocalDateTime.now();
    }
    return parsedDate;
  }

  private String normalize(final String callId) {
    final String normalizedCallId;
    if (callId == null) {
      normalizedCallId = null;
    } else {
      final String trimmed = callId.trim();
      normalizedCallId = trimmed.isEmpty() ? null : trimmed;
    }
    return normalizedCallId;
  }

  /**
   * Deletes archived transcript objects and metadata for a call.
   *
   * @param callId call identifier
   * @return number of deleted archive rows
   */
  @Transactional
  public long purgeArchiveForCall(final String callId) {
    final String normalizedCallId = normalize(callId);
    final long deletedCount;
    if (normalizedCallId == null) {
      deletedCount = 0;
    } else {
      if (s3StorageService != null) {
        archiveRepository
            .findByCallIdOrderByArchivedAtDesc(normalizedCallId)
            .forEach(this::deleteArchiveObjectQuietly);
      }
      deletedCount = archiveRepository.deleteByCallId(normalizedCallId);
    }
    return deletedCount;
  }

  private void deleteArchiveObjectQuietly(final CallTranscriptArchive archive) {
    if (archive != null && archive.getStorageKey() != null && !archive.getStorageKey().isBlank()) {
      try {
        s3StorageService.deleteFile(archive.getStorageKey());
      } catch (Exception ex) {
        if (log.isWarnEnabled()) {
          log.warn(
              "Failed to delete transcript archive object {}: {}",
              archive.getStorageKey(),
              ex.getMessage());
        }
      }
    }
  }

  /** Archived transcript segment payload stored in object storage. */
  private record ArchivedTranscriptSegment(
      String speakerLabel,
      String text,
      Long startMs,
      Long endMs,
      String source,
      Long actorUserId,
      String occurredAt) {}
}
