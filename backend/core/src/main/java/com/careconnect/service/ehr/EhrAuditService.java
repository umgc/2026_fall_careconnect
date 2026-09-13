package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;

/**
 * Fail-soft, hashed-PHI audit of every EHR connect/fetch attempt (Findings R6).
 *
 * <p>Modeled on {@code AiAskAuditService}: writes run in a {@code REQUIRES_NEW} transaction and
 * swallow persistence errors so an audit failure never breaks the request path. Any PHI-bearing
 * detail (e.g. a FHIR resource id) is stored only as {@code SHA-256(detail|userId)}, never raw.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EhrAuditService {

    private final EhrAuditEventRepository repo;

    /** Record a successful/empty/error attempt. {@code detail} is hashed if present. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(Long userId, String source, String eventType,
                       String resourceType, String detail, String outcome) {
        try {
            EhrAuditEvent event = EhrAuditEvent.builder()
                    .userId(userId)
                    .source(source)
                    .eventType(eventType)
                    .resourceType(resourceType)
                    .detailHash(detail == null ? null : hashText(detail, userId))
                    .outcome(outcome)
                    .build();
            repo.save(event);
        } catch (RuntimeException ex) {
            // Fail-soft: never let auditing abort the request.
            log.warn("EHR audit write failed (userId={}, event={}): {}",
                    userId, eventType, ex.getClass().getSimpleName());
        }
    }

    /** Convenience overload for connect/lifecycle events with no resource. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(Long userId, String source, String eventType, String outcome) {
        record(userId, source, eventType, null, null, outcome);
    }

    private static String hashText(String text, Long patientSalt) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest((text + "|" + patientSalt).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception e) {
            return null;
        }
    }
}
