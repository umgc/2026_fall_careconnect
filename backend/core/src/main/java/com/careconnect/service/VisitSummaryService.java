package com.careconnect.service;

import com.careconnect.model.VisitSummary;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * Entry point for visit-summary writers (Task 1.4). Delegates persistence and
 * {@code SUMMARY_CREATED} outbox emission to {@link VisitSummaryPersistenceService}.
 */
@Service
@RequiredArgsConstructor
public class VisitSummaryService {

    private final VisitSummaryPersistenceService persistenceService;

    /**
     * Persists a visit summary row and, when {@code status=SUCCESS}, emits the
     * indexing outbox event consumed by {@code RetrievalIndexService}.
     */
    public VisitSummary persistAndEmit(final VisitSummary summary) {
        return persistenceService.persist(summary);
    }
}
