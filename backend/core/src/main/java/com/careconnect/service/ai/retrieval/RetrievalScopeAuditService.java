package com.careconnect.service.ai.retrieval;

import com.careconnect.model.User;
import com.careconnect.service.ai.audit.AiAskAuditService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Structured audit for Ask AI scope denials (Task 2.6 / REQ-SC-9).
 *
 * <p>Writes a durable {@code SCOPE_DENIED} event through {@link AiAskAuditService}
 * (fail-soft) and mirrors the same correlation id to the application log.
 */
@Service
public class RetrievalScopeAuditService {

    static final String EVENT_TYPE = AiAskAuditService.SCOPE_DENIED;
    static final String DELIVERY_STATUS = "WITHHELD";
    private static final Logger log = LoggerFactory.getLogger(RetrievalScopeAuditService.class);
    private final AiAskAuditService askAuditService;

    public RetrievalScopeAuditService(final AiAskAuditService askAuditService) {
        this.askAuditService = askAuditService;
    }

    /**
     * Records a scope denial and returns the audit id for correlation in HTTP responses.
     *
     * @param caller    authenticated user attempting Ask AI access (may be null in edge cases)
     * @param patientId requested patient entity id
     * @param reason    structured denial reason
     * @param detail    human-readable detail (no query text or retrieved chunks)
     * @return audit id to include on the 403 response
     */
    public UUID logScopeDenied(
            User caller,
            Long patientId,
            ScopeDenialReason reason,
            String detail) {
        UUID auditId = UUID.randomUUID();
        final Long callerUserId = caller != null ? caller.getId() : null;
        log.warn(
                "AI_ASK_AUDIT eventType={} auditId={} callerUserId={} patientId={} "
                        + "denialReason={} deliveryStatus={} retrievalPerformed=false",
                EVENT_TYPE,
                auditId,
                callerUserId,
                patientId,
                reason,
                DELIVERY_STATUS);
        final Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("patientId", patientId);
        payload.put("denialReason", reason == null ? null : reason.name());
        payload.put("deliveryStatus", DELIVERY_STATUS);
        payload.put("retrievalPerformed", false);
        if (detail != null && !detail.isBlank()) {
            payload.put("detail", detail);
        }
        askAuditService.appendStandaloneEvent(auditId, EVENT_TYPE, callerUserId, payload);
        return auditId;
    }
}
