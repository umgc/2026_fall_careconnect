package com.careconnect.service;

import com.careconnect.model.CallSummary;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.repository.CallSummaryRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.SummaryCreatedPayload;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Service that generates, stores, and returns call summaries. */
@Slf4j
@Service
@RequiredArgsConstructor
public class CallSummaryService {

  private static final String TRANSCRIPT_ARCHIVED = "transcriptArchived";
  private static final String DEFAULT_SENTIMENT_LABEL = "ANXIOUS";
  private static final String EMPTY_SUMMARY_HEADLINE = "No transcript captured";
  private static final String EMPTY_SUMMARY_ASSESSMENT =
      "Call transcript was not available for summarization.";
  private static final String FAILED_SUMMARY_HEADLINE = "Summary unavailable";
  private static final String FAILED_SUMMARY_ASSESSMENT =
      "Automated summary could not be generated.";

  /** Repository used to persist generated call summaries. */
  private final CallSummaryRepository summaryRepository;

  /** Service used to read transcript data for summary generation. */
  private final CallTranscriptService transcriptService;

  /** Sentiment service used to build AI-backed summary payloads. */
  private final BedrockSentimentService sentimentService;

  /** JSON mapper used to serialize and deserialize summary payloads. */
  private final ObjectMapper objectMapper;

  /** Emits SUMMARY_CREATED events to the indexing outbox after successful persistence. */
  private final IndexingEventEmitter indexingEventEmitter;

  /**
   * Returns the latest stored summary entity for a call when available.
   *
   * @param callId call identifier
   * @return latest stored summary entity
   */
  public Optional<CallSummary> getLatestSummaryEntity(final String callId) {
    final String normalizedCallId = normalize(callId);
    final Optional<CallSummary> result;
    if (normalizedCallId == null) {
      result = Optional.empty();
    } else {
      result = summaryRepository.findTopByCallIdOrderByGeneratedAtDesc(normalizedCallId);
    }
    return result;
  }

  /**
   * Returns the latest stored summary payload for a call when available.
   *
   * @param callId call identifier
   * @return latest stored summary payload
   */
  public Optional<Map<String, Object>> getLatestSummary(final String callId) {
    return getLatestSummaryEntity(callId).map(this::toResponse);
  }

  /**
   * Generates, stores, and returns a summary for the supplied call.
   *
   * @param callId call identifier
   * @param generatedByUserId generating user identifier, when known
   * @param latestByChannel latest channel sentiment events
   * @return stored summary response payload
   */
  @Transactional 
  public Map<String, Object> generateAndStoreSummary(
      final String callId,
      final Long generatedByUserId,
      final Map<String, CallTelemetryEvent> latestByChannel) {
    final String normalizedCallId = requireCallId(callId);
    final String transcript = transcriptService.buildTranscriptTextForSummary(normalizedCallId);
    final long segmentCount = transcriptService.countSegments(normalizedCallId);
    Map<String, Object> response = Map.of();

    if (transcript.isBlank()) {
      response = buildNoTranscriptResponse(normalizedCallId, generatedByUserId, segmentCount);
    } else {
      final Map<String, BedrockSentimentService.SentimentResult> channelScores =
          toChannelScores(normalizedCallId, latestByChannel);
      response = generateSummaryResponse(
          normalizedCallId,
          transcript,
          generatedByUserId,
          segmentCount,
          channelScores);
    }
    return response;
  }

  private Map<String, Object> buildNoTranscriptResponse(
      final String normalizedCallId,
      final Long generatedByUserId,
      final long segmentCount) {
    final CallSummary summary = new CallSummary();
    summary.setCallId(normalizedCallId);
    summary.setStatus("NO_TRANSCRIPT");
    summary.setTranscriptSegmentCount((int) segmentCount);
    summary.setGeneratedByUserId(generatedByUserId);
    summary.setErrorMessage("No transcript segments were available.");
    summary.setGeneratedAt(LocalDateTime.now());
    summary.setSummaryJson(
        toJsonSafe(emptySummaryPayload(EMPTY_SUMMARY_HEADLINE, EMPTY_SUMMARY_ASSESSMENT)));
    return persistResponse(normalizedCallId, summary);
  }

  private Map<String, Object> generateSummaryResponse(
      final String normalizedCallId,
      final String transcript,
      final Long generatedByUserId,
      final long segmentCount,
      final Map<String, BedrockSentimentService.SentimentResult> channelScores) {
    Map<String, Object> response = Map.of();
    try {
      final Map<String, Object> summaryPayload =
          sentimentService.summarizeTranscript(normalizedCallId, transcript, channelScores);
      final CallSummary stored = buildStoredSummary(
          normalizedCallId,
          generatedByUserId,
          segmentCount,
          "SUCCESS",
          null,
          summaryPayload);
      response = persistResponse(normalizedCallId, stored);
    } catch (Exception ex) {
      logSummaryFailure(normalizedCallId, ex);
      final CallSummary failed = buildStoredSummary(
          normalizedCallId,
          generatedByUserId,
          segmentCount,
          "ERROR",
          ex.getMessage(),
          emptySummaryPayload(FAILED_SUMMARY_HEADLINE, FAILED_SUMMARY_ASSESSMENT));
      response = persistResponse(normalizedCallId, failed);
    }
    return response;
  }

  private CallSummary buildStoredSummary(
      final String normalizedCallId,
      final Long generatedByUserId,
      final long segmentCount,
      final String status,
      final String errorMessage,
      final Map<String, Object> summaryPayload) {
    final CallSummary summary = new CallSummary();
    summary.setCallId(normalizedCallId);
    summary.setStatus(status);
    summary.setTranscriptSegmentCount((int) segmentCount);
    summary.setGeneratedByUserId(generatedByUserId);
    summary.setGeneratedAt(LocalDateTime.now());
    summary.setErrorMessage(errorMessage);
    summary.setRiskLevel(extractStringField(summaryPayload, "riskLevel"));
    summary.setCaregiverVisibility(extractCaregiverVisibility(summaryPayload));
    summary.setSummarizationEngine(extractStringField(summaryPayload, "summarizationEngine"));
    summary.setSummaryJson(toJsonSafe(summaryPayload));
    return summary;
  }

  private Map<String, Object> persistResponse(
      final String normalizedCallId,
      final CallSummary summary) {
    transcriptService.archiveIfEligible(normalizedCallId);
    final CallSummary saved = summaryRepository.save(summary);
    final Map<String, Object> response = toResponse(saved);
    emitIfSuccess(saved);
    response.put(TRANSCRIPT_ARCHIVED, transcriptService.isArchived(normalizedCallId));
    return response;
  }

  private static Map<String, Object> emptySummaryPayload(
      final String headline,
      final String overallAssessment) {
    return Map.of(
        "headline", headline,
        "overallAssessment", overallAssessment,
        "keyConcerns", List.of(),
        "recommendedActions", List.of(),
        "followUpQuestions", List.of());
  }

  private static void logSummaryFailure(final String normalizedCallId, final Exception ex) {
    if (log.isWarnEnabled()) {
      log.warn(
          "Call summary generation failed for callId {}: {}",
          normalizedCallId,
          ex.getMessage());
    }
  }

  private static String requireCallId(final String callId) {
    final String normalizedCallId = normalize(callId);
    if (normalizedCallId == null) {
      throw new IllegalArgumentException("callId is required");
    }
    return normalizedCallId;
  }

  private Map<String, BedrockSentimentService.SentimentResult> toChannelScores(
      final String callId,
      final Map<String, CallTelemetryEvent> latestByChannel) {
    final Map<String, BedrockSentimentService.SentimentResult> scores;
    if (latestByChannel == null || latestByChannel.isEmpty()) {
      scores = Map.of();
    } else {
      scores =
          latestByChannel.entrySet().stream()
              .filter(
                  entry ->
                      entry.getValue() != null
                          && entry.getValue().getSentimentScore() != null)
              .collect(
                  Collectors.toMap(
                      entry -> normalizeChannel(entry.getKey()),
                      entry -> toSentimentResult(callId, entry),
                      (left, right) -> left,
                      LinkedHashMap::new));
    }
    return scores;
  }

  private BedrockSentimentService.SentimentResult toSentimentResult(
      final String callId,
      final Map.Entry<String, CallTelemetryEvent> entry) {
    final CallTelemetryEvent event = entry.getValue();
    return new BedrockSentimentService.SentimentResult(
        event.getSentimentScore(),
        event.getSentimentLabel() == null
            ? DEFAULT_SENTIMENT_LABEL
            : event.getSentimentLabel(),
        event.getSentimentNotes() == null ? "" : event.getSentimentNotes(),
        normalizeChannel(entry.getKey()),
        callId,
        event.getAnalysisTimestamp() == null
            ? System.currentTimeMillis()
            : event.getAnalysisTimestamp(),
        false);
  }

  private static String normalizeChannel(final String channel) {
    return channel.trim().toUpperCase(Locale.ROOT);
  }

  /**
   * Emits SUMMARY_CREATED for a persisted summary when its status is
   * SUCCESS. Per Ravichandra Vasireddy's 2026-07-03 indexing contract,
   * NO_TRANSCRIPT and ERROR summaries are not indexed. patientId is
   * read from the entity, nullable until callers populate it.
   *
   * @param summary persisted call summary
   */
  private void emitIfSuccess(final CallSummary summary) {
    if (summary == null || !"SUCCESS".equals(summary.getStatus())) {
      return;
    }
    final SummaryCreatedPayload payload = new SummaryCreatedPayload(
        "call",
        "call_summaries",
        summary.getId(),
        summary.getCallId(),
        summary.getPatientId(),
        summary.getStatus(),
        summary.getGeneratedAt(),
        summary.getTranscriptSegmentCount(),
        summary.getCaregiverVisibility(),
        summary.getSummarizationEngine(),
        sha256(summary.getSummaryJson()));
    indexingEventEmitter.emitSummaryCreated(payload);
  }

  /**
   * Computes {@code sha256:<hex>} of the given input for the
   * SUMMARY_CREATED payload's contentHash field. Consumers use this
   * to skip re-embedding an unchanged summary.
   */
  private String sha256(final String input) {
    if (input == null) {
      return null;
    }
    try {
      final MessageDigest digest = MessageDigest.getInstance("SHA-256");
      final byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));
      final StringBuilder hex = new StringBuilder(hash.length * 2);
      for (final byte b : hash) {
        hex.append(String.format("%02x", b));
      }
      return "sha256:" + hex;
    } catch (final NoSuchAlgorithmException e) {
      throw new IllegalStateException("SHA-256 not available", e);
    }
  }

  private Map<String, Object> toResponse(final CallSummary summary) {
    Map<String, Object> payload = new LinkedHashMap<>();
    if (summary.getSummaryJson() != null && !summary.getSummaryJson().isBlank()) {
      try {
        payload =
            objectMapper.readValue(
                summary.getSummaryJson(), new TypeReference<Map<String, Object>>() {});
      } catch (Exception ignored) {
        payload = new LinkedHashMap<>();
      }
    }

    final Map<String, Object> response = new LinkedHashMap<>();
    response.put("callId", summary.getCallId());
    response.put("status", summary.getStatus());
    response.put("generatedAt", summary.getGeneratedAt());
    response.put("transcriptSegmentCount", summary.getTranscriptSegmentCount());
    response.put("generatedByUserId", summary.getGeneratedByUserId());
    if (summary.getErrorMessage() != null && !summary.getErrorMessage().isBlank()) {
      response.put("errorMessage", summary.getErrorMessage());
    }
    response.put(TRANSCRIPT_ARCHIVED, transcriptService.isArchived(summary.getCallId()));
    response.put("summary", payload);
    return response;
  }

  /**
   * Reads an optional string field from the Bedrock summary payload,
   * returning null when the field is absent or blank. Preserves
   * entity nullability for downstream consumers that treat null as
   * "not classified" (see WBS 3.4.3, 3.4.4).
   */
  private static String extractStringField(
      final Map<String, Object> payload,
      final String fieldName) {
    final Object value = payload.get(fieldName);
    final String result;
    if (value == null) {
      result = null;
    } else {
      final String trimmed = value.toString().trim();
      result = trimmed.isEmpty() ? null : trimmed;
    }
    return result;
  }

  /**
   * Extracts caregiver_visibility from the Bedrock summary payload,
   * defaulting to on_consent when absent so that caregivers cannot
   * view the summary unless consent is granted.
   */
  private static String extractCaregiverVisibility(
      final Map<String, Object> payload) {
    final String raw = extractStringField(payload, "caregiverVisibility");
    return raw == null ? "on_consent" : raw;
  }

  private String toJsonSafe(final Object value) {
    String json = "{}";
    try {
      json = objectMapper.writeValueAsString(value);
    } catch (Exception ex) {
      json = "{}";
    }
    return json;
  }

  private static String normalize(final String callId) {
    final String normalized;
    if (callId == null) {
      normalized = null;
    } else {
      final String trimmed = callId.trim();
      normalized = trimmed.isEmpty() ? null : trimmed;
    }
    return normalized;
  }

  /**
   * Deletes stored summaries for a call.
   *
   * @param callId call identifier
   * @return number of deleted rows
   */
  @Transactional
  public long deleteSummariesForCall(final String callId) {
    final String normalizedCallId = normalize(callId);
    final long deleted;
    if (normalizedCallId == null) {
      deleted = 0;
    } else {
      deleted = summaryRepository.deleteByCallId(normalizedCallId);
    }
    return deleted;
  }
}
