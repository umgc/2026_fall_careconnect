package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
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
 * Fail-soft, hashed-PHI audit of every EHR connect/fetch attempt (Findings R6).
 *
 * <p>Modeled on {@code AiAskAuditService}: writes run in a {@code REQUIRES_NEW} transaction and
 * swallow persistence errors so an audit failure never breaks the request path. Any PHI-bearing
 * detail (e.g. a FHIR resource id) is stored only as {@code SHA-256(detail|userId)}, never raw.
 *
 * <p>Persists the canonical {@link EhrAuditEvent} (ADR-08). For the Epic self-connect flow the
 * connecting user is also the patient, so {@code userId} maps to both {@code patientId} and
 * {@code actorUserId}. The operation {@code eventType} and the hashed detail have no dedicated
 * canonical column, so they are carried in the non-PHI {@code details} map; the coarse string
 * outcome is mapped onto {@link EhrRetrievalOutcome}.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EhrAuditService {

    /** Outcome vocabulary accepted by {@link #record}; mapped to {@link EhrRetrievalOutcome}. */
    public static final String OUTCOME_OK = "OK";
    public static final String OUTCOME_EMPTY = "EMPTY";
    public static final String OUTCOME_ERROR = "ERROR";

    private final EhrAuditEventRepository repo;

    /** Record a successful/empty/error attempt. {@code detail} is hashed if present. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(Long userId, String source, String eventType,
                       String resourceType, String detail, String outcome) {
        try {
            final Map<String, Object> details = new LinkedHashMap<>();
            if (eventType != null) {
                details.put("eventType", eventType);
            }
            if (detail != null) {
                details.put("detailHash", hashText(detail, userId));
            }
            EhrAuditEvent event = EhrAuditEvent.builder()
                    // Epic self-connect: the connecting user is both the patient and the actor.
                    .patientId(userId)
                    .actorUserId(userId)
                    .source(source)
                    // resource_type is NOT NULL; fall back to the operation when no resource applies.
                    .resourceType(resourceType != null ? resourceType : eventType)
                    .outcome(mapOutcome(outcome))
                    .details(details.isEmpty() ? null : details)
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
