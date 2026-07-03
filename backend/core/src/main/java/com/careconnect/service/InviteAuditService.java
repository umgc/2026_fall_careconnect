package com.careconnect.service;

import com.careconnect.model.InviteTokenAudit;
import com.careconnect.repository.InviteTokenAuditRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Dedicated bean for writing invite audit rows.
 *
 * Extracted from InviteTokenService so that {@link #recordInNewTransaction} is
 * invoked ACROSS a bean boundary. Spring's transactional AOP is proxy-based:
 * a self-invocation (this.method()) bypasses the proxy and silently ignores
 * @Transactional. By living in its own @Service, these methods are always
 * called through the proxy, so REQUIRES_NEW is honoured — audit writes from
 * read-only flows (e.g. previewInvite) run in their own transaction instead of
 * failing inside the caller's read-only transaction.
 *
 * Audit writes are best-effort: any failure is logged and swallowed so audit
 * problems never break the business flow.
 */
@Service
public class InviteAuditService {

    private static final Logger log = LoggerFactory.getLogger(InviteAuditService.class);

    private final InviteTokenAuditRepository auditRepository;

    public InviteAuditService(InviteTokenAuditRepository auditRepository) {
        this.auditRepository = auditRepository;
    }

    /**
     * Write an audit row in the CALLER's transaction (used by mutating flows
     * such as create/accept/revoke, which already have a read-write tx). Uses
     * default REQUIRED propagation: it joins the caller's transaction when one
     * exists, so the audit commits/rolls back together with the business change.
     */
    @Transactional
    public void record(Long tokenId, String eventType, Long actorUserId, String actorIp, String detail) {
        persist(tokenId, eventType, actorUserId, actorIp, detail);
    }

    /**
     * Write an audit row in a NEW, independent transaction. Used by read-only
     * flows (e.g. previewInvite) so the write does not run inside — and fail —
     * the caller's read-only transaction. Because this bean is called through
     * the Spring proxy, REQUIRES_NEW is actually applied.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordInNewTransaction(Long tokenId, String eventType, Long actorUserId,
                                       String actorIp, String detail) {
        persist(tokenId, eventType, actorUserId, actorIp, detail);
    }

    private void persist(Long tokenId, String eventType, Long actorUserId, String actorIp, String detail) {
        try {
            auditRepository.save(new InviteTokenAudit(tokenId, eventType, actorUserId, actorIp, detail));
        } catch (Exception e) {
            log.error("Failed to write invite audit: tokenId={}, event={}", tokenId, eventType, e);
        }
    }
}
