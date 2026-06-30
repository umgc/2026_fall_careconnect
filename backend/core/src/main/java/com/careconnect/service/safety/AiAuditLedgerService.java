package com.careconnect.service.safety;

import com.careconnect.model.safety.AiAuditLedger;
import com.careconnect.model.safety.AuditEventType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.repository.safety.AiAuditLedgerRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;

/**
 * WBS 3.15.6
 * Writes immutable AI governance events to the audit ledger
 *
 * How to use it from any AI feature:
 * <pre>
 *   auditLedgerService.logQuery(AuditSourceFeature.ASK_AI, userId, patientId, sessionId,
 *       Map.of("query", queryText));
 * </pre>
 *
 * Failures are caught / logged and audit recording should not crash the caller
 */
@Service
@RequiredArgsConstructor
public class AiAuditLedgerService {

    private static final Logger log = LoggerFactory.getLogger(AiAuditLedgerService.class);

    private final AiAuditLedgerRepository repository;

    /**
     * Core method stores one audit event
     * Returns the saved entity, or the unsaved entity if the DB fails
     * guarantees that write commits are their own atomic transactions
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public AiAuditLedger log(AuditEventType eventType,
                              AuditSourceFeature sourceFeature,
                              Long actorUserId,
                              Long patientId,
                              String sessionId,
                              Map<String, Object> payload) {
        AiAuditLedger entry = AiAuditLedger.builder()
                .eventType(eventType.name())
                .sourceFeature(sourceFeature.name())
                .actorUserId(actorUserId)
                .patientId(patientId)
                .sessionId(sessionId)
                .payload(payload)
                .build();
        try {
            AiAuditLedger saved = repository.save(entry);
            log.info("AI_AUDIT type={} feature={} actor={} patient={} session={}",
                    eventType, sourceFeature, actorUserId, patientId, sessionId);
            return saved;
        } catch (Exception e) {
            log.error("AI_AUDIT_FAILURE — could not persist ledger entry: type={} feature={} actor={} patient={}",
                    eventType, sourceFeature, actorUserId, patientId, e);
            return entry;
        }
    }

    public AiAuditLedger logQuery(AuditSourceFeature source, Long actorUserId, Long patientId,
                                   String sessionId, Map<String, Object> payload) {
        return log(AuditEventType.QUERY, source, actorUserId, patientId, sessionId, payload);
    }

    public AiAuditLedger logResponse(AuditSourceFeature source, Long actorUserId, Long patientId,
                                      String sessionId, Map<String, Object> payload) {
        return log(AuditEventType.RESPONSE, source, actorUserId, patientId, sessionId, payload);
    }

    public AiAuditLedger logValidation(AuditSourceFeature source, Long actorUserId, Long patientId,
                                        String sessionId, Map<String, Object> payload) {
        return log(AuditEventType.VALIDATION, source, actorUserId, patientId, sessionId, payload);
    }

    public AiAuditLedger logConfirmation(AuditSourceFeature source, Long actorUserId, Long patientId,
                                          String sessionId, Map<String, Object> payload) {
        return log(AuditEventType.CONFIRMATION, source, actorUserId, patientId, sessionId, payload);
    }
}
