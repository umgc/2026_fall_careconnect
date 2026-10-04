package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Writes one {@link EhrAuditEvent} per retrieval attempt against an external EHR source.
 * Adapters call this instead of touching the repository directly, so every source records
 * attempts the same way.
 */
@Component
@RequiredArgsConstructor
public class EhrAuditLogger {

    private final EhrAuditEventRepository repo;

    /**
     * @param details attempt metadata only. Never pass access tokens (NFR-SEC-03) or
     *                retrieved clinical content.
     */
    public void log(final Long patientId,
                    final String source,
                    final String resourceType,
                    final EhrRetrievalOutcome outcome,
                    final Long actorUserId,
                    final Integer recordCount,
                    final Map<String, Object> details) {
        repo.save(EhrAuditEvent.builder()
                .patientId(patientId)
                .source(source)
                .resourceType(resourceType)
                .outcome(outcome)
                .actorUserId(actorUserId)
                .recordCount(recordCount)
                .details(details)
                .build());
    }
}
