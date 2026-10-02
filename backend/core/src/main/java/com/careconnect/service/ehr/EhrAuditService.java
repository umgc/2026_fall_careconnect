package com.careconnect.service.ehr;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.repository.PatientRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Fail-soft, hashed-PHI audit of every EHR connect/fetch attempt (Findings R6), writing the
 * canonical {@code ehr_audit_event} through {@link EhrAuditLogger} (Team E brief S4 — the one
 * blessed writer of that table).
 *
 * <p>This is the userId-facing façade the Epic adapters call. It bridges a CareConnect
 * {@code userId} to the canonical {@code patient_id} via {@link PatientRepository#findByUserId}
 * (Epic self-connect: the connecting user is both patient and actor), maps the coarse string
 * outcome onto {@link EhrRetrievalOutcome}, and carries the operation {@code eventType} plus a
 * hashed detail — neither of which has a canonical column — in the non-PHI {@code details} map.
 *
 * <p>Writes run in a {@code REQUIRES_NEW} transaction and swallow persistence errors so an audit
 * failure never breaks the request path. Any PHI-bearing detail is stored only as
 * {@code SHA-256(detail|userId)}, never raw.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EhrAuditService {

    /** Outcome vocabulary accepted by {@link #record}; mapped to {@link EhrRetrievalOutcome}. */
    public static final String OUTCOME_OK = "OK";
    public static final String OUTCOME_EMPTY = "EMPTY";
    public static final String OUTCOME_ERROR = "ERROR";

    private final EhrAuditLogger auditLogger;
    private final PatientRepository patientRepository;

    /** Record a successful/empty/error attempt. {@code detail} is hashed if present. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(Long userId, String source, String eventType,
                       String resourceType, String detail, String outcome) {
        try {
            final Long patientId = patientRepository.findByUserId(userId)
                    .map(Patient::getId)
                    .orElse(null);
            if (patientId == null) {
                // ehr_audit_event.patient_id is NOT NULL; a user with no patient row (e.g. a
                // caregiver) cannot be audited against the canonical table. Skip, don't crash.
                log.warn("EHR audit skipped: no patient row for user {} (event={})", userId, eventType);
                return;
            }
            final Map<String, Object> details = new LinkedHashMap<>();
            if (eventType != null) {
                details.put("eventType", eventType);
            }
            if (detail != null) {
                details.put("detailHash", hashText(detail, userId));
            }
            auditLogger.log(
                    patientId,
                    source,
                    resourceType != null ? resourceType : eventType,
                    mapOutcome(outcome),
                    userId,                       // actorUserId: the user who triggered the attempt
                    null,                         // recordCount: not tracked at this call site
                    details.isEmpty() ? null : details);
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

    /** Map the coarse string outcome vocabulary onto the canonical retrieval-outcome enum. */
    private static EhrRetrievalOutcome mapOutcome(String outcome) {
        if (outcome == null) {
            return EhrRetrievalOutcome.FAILURE;
        }
        return switch (outcome) {
            case OUTCOME_OK -> EhrRetrievalOutcome.SUCCESS;
            case OUTCOME_EMPTY -> EhrRetrievalOutcome.EMPTY;
            case "RETRY" -> EhrRetrievalOutcome.RETRY;
            default -> EhrRetrievalOutcome.FAILURE;
        };
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
