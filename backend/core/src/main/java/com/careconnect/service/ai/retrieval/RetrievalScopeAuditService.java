package com.careconnect.service.ai.retrieval;

import com.careconnect.model.User;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.UUID;

/**
 * Structured audit logging for Ask AI scope denials (Task 2.6, REQ-SC-9 precursor).
 *
 * <p>Writes {@code SCOPE_DENIED} events with no retrieval output. Full immutable ledger
 * persistence lands in Task 6.8 ({@code AiAuditService}).
 */
@Service
public class RetrievalScopeAuditService {

    private static final Logger log = LoggerFactory.getLogger(RetrievalScopeAuditService.class);

    static final String EVENT_TYPE = "SCOPE_DENIED";
    static final String DELIVERY_STATUS = "WITHHELD";

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
        log.warn(
                "AI_ASK_AUDIT eventType={} auditId={} callerUserId={} callerEmail={} patientId={} "
                        + "denialReason={} detail={} deliveryStatus={} retrievalPerformed=false",
                EVENT_TYPE,
                auditId,
                caller != null ? caller.getId() : null,
                caller != null ? caller.getEmail() : null,
                patientId,
                reason,
                detail,
                DELIVERY_STATUS);
        return auditId;
    }
}
