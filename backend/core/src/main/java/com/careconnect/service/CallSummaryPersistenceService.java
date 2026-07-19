package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.model.CallSummary;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.util.ContentHashUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Owns the short atomic persistence phase for generated call summaries.
 */
@Service
@RequiredArgsConstructor
public class CallSummaryPersistenceService {

    private final CallSummaryRepository summaryRepository;
    private final IndexingEventEmitter indexingEventEmitter;

    /**
     * Persists the summary and its SUCCESS outbox event in the same transaction.
     */
    @Transactional
    public CallSummary persist(final CallSummary summary) {
        final CallSummary saved = summaryRepository.save(summary);
        if ("SUCCESS".equals(saved.getStatus())) {
            if (saved.getPatientId() == null) {
                throw new IllegalStateException(
                        "Successful call summary requires authoritative patient ownership");
            }
            indexingEventEmitter.emitSummaryCreated(new SummaryCreatedPayload(
                    "call",
                    "call_summaries",
                    saved.getId(),
                    saved.getCallId(),
                    saved.getPatientId(),
                    saved.getStatus(),
                    saved.getGeneratedAt(),
                    saved.getTranscriptSegmentCount(),
                    saved.getCaregiverVisibility(),
                    saved.getSummarizationEngine(),
                    ContentHashUtil.sha256(saved.getSummaryJson())));
        }
        return saved;
    }
}
