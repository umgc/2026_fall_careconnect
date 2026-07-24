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

    private static final String SUCCESS = "SUCCESS";
    private static final String NO_TRANSCRIPT = "NO_TRANSCRIPT";

    private final CallSummaryRepository summaryRepository;
    private final IndexingEventEmitter indexingEventEmitter;

    /**
     * Persists one summary per call/snapshot/model key and its SUCCESS outbox event
     * in the same transaction.
     */
    @Transactional
    public CallSummary persist(final CallSummary summary) {
        final String lockKey = "call-summary:"
                + summary.getCallId() + ":"
                + summary.getTranscriptSnapshotVersion() + ":"
                + summary.getModelConfigVersion();
        summaryRepository.acquireGenerationLock(lockKey);
        final CallSummary existing = summaryRepository
                .findByCallIdAndTranscriptSnapshotVersionAndModelConfigVersion(
                        summary.getCallId(),
                        summary.getTranscriptSnapshotVersion(),
                        summary.getModelConfigVersion())
                .orElse(null);
        if (existing != null) {
            if (isTerminalSuccess(existing)) {
                return existing;
            }
            copyAttempt(summary, existing);
            final CallSummary recovered = summaryRepository.save(existing);
            emitSummaryCreatedIfSuccessful(recovered);
            return recovered;
        }
        final CallSummary saved = summaryRepository.save(summary);
        emitSummaryCreatedIfSuccessful(saved);
        return saved;
    }

    private void emitSummaryCreatedIfSuccessful(final CallSummary saved) {
        if (SUCCESS.equals(saved.getStatus())) {
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
    }

    private static boolean isTerminalSuccess(final CallSummary summary) {
        return SUCCESS.equals(summary.getStatus()) || NO_TRANSCRIPT.equals(summary.getStatus());
    }

    private static void copyAttempt(final CallSummary source, final CallSummary target) {
        target.setPatientId(source.getPatientId());
        target.setSummaryJson(source.getSummaryJson());
        target.setStatus(source.getStatus());
        target.setTranscriptSegmentCount(source.getTranscriptSegmentCount());
        target.setGeneratedByUserId(source.getGeneratedByUserId());
        target.setErrorMessage(source.getErrorMessage());
        target.setGeneratedAt(source.getGeneratedAt());
        target.setRiskLevel(source.getRiskLevel());
        target.setCaregiverVisibility(source.getCaregiverVisibility());
        target.setSummaryConfidence(source.getSummaryConfidence());
        target.setSummarizationEngine(source.getSummarizationEngine());
        target.setTranscriptAvailable(source.getTranscriptAvailable());
    }
}
