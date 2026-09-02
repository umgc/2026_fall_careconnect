package com.careconnect.service;

import com.careconnect.model.VisitSummary;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.VisitSummaryRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.Optional;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Entry point for visit-summary writers (Task 1.4). Delegates persistence and
 * {@code SUMMARY_CREATED} outbox emission to {@link VisitSummaryPersistenceService}, and
 * additionally produces summaries directly from a completed {@link ScheduledVisit} so that
 * Ask AI can retrieve visit context even when no call transcript exists.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VisitSummaryService {

    private static final String STATUS_SUCCESS = "SUCCESS";
    private static final String STATUS_ERROR = "ERROR";
    private static final String STATUS_NO_TRANSCRIPT = "NO_TRANSCRIPT";
    private static final String CAREGIVER_VISIBILITY_ON_CONSENT = "on_consent";
    private static final String EMPTY_OVERVIEW_JSON = "{}";

    private final VisitSummaryPersistenceService persistenceService;
    private final VisitSummaryRepository visitSummaryRepository;
    private final ScheduledVisitRepository scheduledVisitRepository;
    private final BedrockSentimentService bedrockSentimentService;
    private final ObjectMapper objectMapper;

    private static String buildSourceText(final ScheduledVisit visit, final String notes) {
        final StringBuilder builder = new StringBuilder();
        if (visit.getServiceType() != null && !visit.getServiceType().isBlank()) {
            builder.append("Service: ").append(visit.getServiceType()).append('\n');
        }
        if (visit.getScheduledDate() != null) {
            builder.append("Date: ").append(visit.getScheduledDate());
            if (visit.getScheduledTime() != null) {
                builder.append(' ').append(visit.getScheduledTime());
            }
            builder.append('\n');
        }
        builder.append("Notes: ").append(notes);
        return builder.toString();
    }

    /**
     * Persists a visit summary row and, when {@code status=SUCCESS}, emits the
     * indexing outbox event consumed by {@code RetrievalIndexService}.
     */
    public VisitSummary persistAndEmit(final VisitSummary summary) {
        return persistenceService.persist(summary);
    }

    /**
     * Generates and stores a visit summary for the given scheduled visit.
     *
     * <p>Idempotent for successful summaries: when a {@code SUCCESS} row already exists for
     * the visit, that row is returned without re-calling the summarization model (unless
     * {@code force} is true). Both EVV completion and status-update callers may invoke this
     * safely.
     *
     * <p>When the visit has no notes, a {@code NO_TRANSCRIPT} summary is stored with an
     * empty overview payload instead of calling the summarization model.
     *
     * @param visitId           scheduled visit identifier
     * @param generatedByUserId user that triggered generation, when known
     * @return the persisted visit summary
     */
    public VisitSummary generateAndStoreSummary(
            final Long visitId, final Long generatedByUserId) {
        return generateAndStoreSummary(visitId, generatedByUserId, false);
    }

    /**
     * @param force when true, regenerates even if a SUCCESS summary already exists
     */
    public VisitSummary generateAndStoreSummary(
            final Long visitId, final Long generatedByUserId, final boolean force) {
        if (visitId == null) {
            throw new IllegalArgumentException("visitId is required");
        }
        final String visitIdKey = String.valueOf(visitId);
        if (!force) {
            final Optional<VisitSummary> existing =
                    visitSummaryRepository.findTopByVisitIdOrderByGeneratedAtDesc(visitIdKey);
            if (existing.isPresent()
                    && STATUS_SUCCESS.equalsIgnoreCase(
                    existing.get().getStatus() == null
                            ? ""
                            : existing.get().getStatus().trim())) {
                if (log.isDebugEnabled()) {
                    log.debug(
                            "Skipping visit summary generation for visitId={} — SUCCESS already exists",
                            visitId);
                }
                return existing.get();
            }
        }

        final ScheduledVisit visit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() ->
                        new IllegalArgumentException("Scheduled visit not found: " + visitId));

        final VisitSummary summary = new VisitSummary();
        summary.setVisitId(visitIdKey);
        summary.setPatientId(visit.getPatientId());
        summary.setGeneratedByUserId(generatedByUserId);
        summary.setGeneratedAt(LocalDateTime.now(ZoneOffset.UTC));
        summary.setTranscriptSegmentCount(0);
        summary.setCaregiverVisibility(CAREGIVER_VISIBILITY_ON_CONSENT);
        summary.setModelConfigVersion(bedrockSentimentService.summaryModelConfigVersion());

        final String notes = visit.getNotes();
        if (notes == null || notes.isBlank()) {
            summary.setStatus(STATUS_NO_TRANSCRIPT);
            summary.setSummaryJson(EMPTY_OVERVIEW_JSON);
            summary.setErrorMessage("No visit notes were available for summarization.");
        } else {
            populateGeneratedSummary(summary, visit, notes);
        }

        return persistenceService.persist(summary);
    }

    private void populateGeneratedSummary(
            final VisitSummary summary, final ScheduledVisit visit, final String notes) {
        final String sourceText = buildSourceText(visit, notes);
        try {
            final Map<String, Object> summaryPayload = bedrockSentimentService.summarizeTranscript(
                    "visit-" + visit.getId(), sourceText, Map.of());
            summary.setStatus(STATUS_SUCCESS);
            summary.setSummaryJson(toJsonSafe(summaryPayload));
        } catch (ModelInferenceException ex) {
            if (log.isWarnEnabled()) {
                log.warn(
                        "Visit summary generation failed for visitId {}: {}",
                        visit.getId(), ex.getMessage());
            }
            summary.setStatus(STATUS_ERROR);
            summary.setErrorMessage(ex.getMessage());
            summary.setSummaryJson(EMPTY_OVERVIEW_JSON);
        }
        summary.setSummarizationEngine(bedrockSentimentService.summaryEngine());
    }

    private String toJsonSafe(final Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to serialize visit summary payload", ex);
        }
    }
}
