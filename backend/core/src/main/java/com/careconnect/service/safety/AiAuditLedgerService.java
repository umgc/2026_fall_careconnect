package com.careconnect.service.safety;

import com.careconnect.model.safety.AiAuditLedger;
import com.careconnect.model.safety.AuditEventType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.repository.safety.AiAuditLedgerRepository;
import com.careconnect.service.MedicalDataAnonymizer;
import com.careconnect.service.MedicalDataAnonymizer.AnonymizationLevel;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * WBS 3.15.6
 * Writes immutable AI governance events to the audit ledger
 * <p>
 * How to use it from any AI feature:
 * <pre>
 *   auditLedgerService.logQuery(AuditSourceFeature.ASK_AI, userId, patientId, sessionId,
 *       Map.of("query", queryText));
 * </pre>
 * <p>
 * Failures are caught / logged and audit recording should not crash the caller
 */
@Service
@RequiredArgsConstructor
public class AiAuditLedgerService {

    /**
     * Max characters kept in each free-text payload value. The ledger stores a
     * small note for traceability to minimize PHI exposure and
     * storage
     */
    static final int MAX_VALUE_LENGTH = 500;
    private static final Logger log = LoggerFactory.getLogger(AiAuditLedgerService.class);
    private static final String TRUNCATION_SUFFIX = "…[truncated]";

    private final AiAuditLedgerRepository repository;
    private final MedicalDataAnonymizer anonymizer;

    /**
     * stores one audit event
     * Returns the saved entity, or the unsaved entity if the DB fails
     * guarantees that write commits are atomic
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
                .payload(minimizePayload(payload, patientId))
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

    /**
     * Each String value is redacted and truncated to a small summary
     * Non-string values (counts, flags, ids) are metadata
     * Never throws, any failures just truncate the value
     */
    Map<String, Object> minimizePayload(Map<String, Object> payload, Long patientId) {
        if (payload == null || payload.isEmpty()) {
            return payload;
        }
        long pseudoKey = patientId != null ? patientId : 0L;
        Map<String, Object> minimized = new LinkedHashMap<>(payload.size());
        for (Map.Entry<String, Object> e : payload.entrySet()) {
            Object value = e.getValue();
            if (value instanceof String text) {
                minimized.put(e.getKey(), minimizeText(text, pseudoKey));
            } else {
                minimized.put(e.getKey(), value);
            }
        }
        return minimized;
    }

    private String minimizeText(String text, long pseudoKey) {
        if (text == null) {
            return null;
        }
        String redacted;
        try {
            redacted = anonymizer.anonymizePatientContext(text, pseudoKey, AnonymizationLevel.MODERATE);
        } catch (Exception ex) {
            log.warn("Payload redaction failed; storing truncated excerpt only: {}", ex.getMessage());
            redacted = text;
        }
        return truncate(redacted);
    }

    private String truncate(String text) {
        if (text == null || text.length() <= MAX_VALUE_LENGTH) {
            return text;
        }
        return text.substring(0, MAX_VALUE_LENGTH) + TRUNCATION_SUFFIX;
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
