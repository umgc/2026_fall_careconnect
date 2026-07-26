package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.model.VisitSummary;
import com.careconnect.repository.VisitSummaryRepository;
import com.careconnect.util.ContentHashUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Owns atomic persistence + {@code SUMMARY_CREATED} emission for visit summaries
 * (Task 1.4 emitter mirror of {@link CallSummaryPersistenceService}).
 */
@Service
@RequiredArgsConstructor
public class VisitSummaryPersistenceService {

    private static final String SUCCESS = "SUCCESS";

    private final VisitSummaryRepository visitSummaryRepository;
    private final IndexingEventEmitter indexingEventEmitter;

    /**
     * Persists a visit summary and emits {@code SUMMARY_CREATED} when status is SUCCESS.
     */
    @Transactional
    public VisitSummary persist(final VisitSummary summary) {
        if (summary == null) {
            throw new IllegalArgumentException("VisitSummary is required");
        }
        final VisitSummary saved = visitSummaryRepository.save(summary);
        emitSummaryCreatedIfSuccessful(saved);
        return saved;
    }

    private void emitSummaryCreatedIfSuccessful(final VisitSummary saved) {
        if (!SUCCESS.equalsIgnoreCase(
                saved.getStatus() == null ? "" : saved.getStatus().trim())) {
            return;
        }
        if (saved.getPatientId() == null) {
            throw new IllegalStateException(
                    "Successful visit summary requires authoritative patient ownership");
        }
        if (saved.getId() == null) {
            throw new IllegalStateException("Successful visit summary requires a persisted id");
        }
        indexingEventEmitter.emitSummaryCreated(new SummaryCreatedPayload(
                "visit",
                "visit_summaries",
                saved.getId(),
                null,
                saved.getPatientId(),
                saved.getStatus(),
                saved.getGeneratedAt(),
                saved.getTranscriptSegmentCount(),
                saved.getCaregiverVisibility(),
                saved.getSummarizationEngine(),
                ContentHashUtil.sha256(saved.getSummaryJson())));
    }
}
