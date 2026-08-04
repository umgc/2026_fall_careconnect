package com.careconnect.summary.safety;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.service.safety.AiAuditLedgerService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Seam between the Call &amp; Visit Summaries workstream and David's Safety &amp; Consent
 * services (Confirmation Service + AI Audit Ledger).
 *
 * <h2>Design notes</h2>
 * <ul>
 *   <li>{@link #gateConfirmables} calls {@link ConfirmationService#createItem} for each
 *       item that should be held PENDING. It runs inside the CALLER'S transaction
 *       (David's createItem is REQUIRED propagation). The caller is responsible for
 *       wrapping the summary save + gate in a single {@code @Transactional} method so
 *       summary persistence and PENDING confirmation creation commit or roll back
 *       together. {@code SummarySafetyAtomicityIT} canaries this contract at the
 *       repository level.</li>
 *   <li>{@link #logExtractionResponse} delegates to David's ledger which runs in its own
 *       REQUIRES_NEW transaction, so an audit-log failure will never roll back the
 *       caller's work. Belt-and-suspenders try/catch here in case that ever changes.</li>
 *   <li>We do NOT log CONFIRMATION events from here — David's ConfirmationService
 *       self-logs those internally when confirm/dismiss is called through his API.</li>
 * </ul>
 *
 * <h2>Correlation key convention</h2>
 * {@code summaryId} (persisted PK) == {@code confirmationItem.referenceId} ==
 * {@code auditLedger.summaryId}. This lets audit chains join:
 * ledger RESPONSE &rarr; summary &rarr; confirmation item &rarr; ledger CONFIRMATION.
 */
@Service
public class SummarySafetyGateway {

    private static final Logger log = LoggerFactory.getLogger(SummarySafetyGateway.class);

    private final ConfirmationService confirmationService;
    private final AiAuditLedgerService auditLedgerService;
    private final ObjectMapper objectMapper;

    public SummarySafetyGateway(
            ConfirmationService confirmationService,
            AiAuditLedgerService auditLedgerService,
            ObjectMapper objectMapper) {
        this.confirmationService = confirmationService;
        this.auditLedgerService = auditLedgerService;
        this.objectMapper = objectMapper;
    }

    /**
     * Create a PENDING confirmation gate for each confirmable item in the context.
     * <p>
     * <b>MUST be called within the caller's {@code @Transactional} method</b> so the
     * summary and its gates commit atomically. Because David's {@code createItem} uses
     * REQUIRED propagation, calling from a non-transactional context would create each
     * gate in its own transaction, breaking the atomicity contract.
     */
    public void gateConfirmables(SummarySafetyContext context) {
        String referenceId = String.valueOf(context.summaryId());
        for (SummarySafetyContext.Confirmable c : context.confirmables()) {
            String payloadJson = toReviewerJson(c, context.summaryId());
            confirmationService.createItem(
                    ConfirmationSourceType.SUMMARY,
                    payloadJson,
                    referenceId,
                    context.userId()
            );
        }
    }

    /**
     * Emit a RESPONSE/SUMMARY audit event for the extraction result.
     * <p>
     * Runs in David's REQUIRES_NEW transaction — never rolls back the caller. The
     * try/catch here is belt-and-suspenders: David's ledger already catches internally,
     * but if that guarantee ever slips, we log at WARN rather than propagate.
     */
    public void logExtractionResponse(SummarySafetyContext context, int itemCount) {
        try {
            auditLedgerService.logResponse(
                    AuditSourceFeature.SUMMARY,
                    context.userId(),
                    context.patientId(),
                    context.sessionId(),
                    Map.of(
                            "summaryId", context.summaryId(),
                            "itemCount", itemCount
                    )
            );
        } catch (Exception e) {
            log.warn("audit ledger call threw despite REQUIRES_NEW guard: {}",
                    e.getMessage(), e);
        }
    }

    private String toReviewerJson(SummarySafetyContext.Confirmable c, Long summaryId) {
        try {
            return objectMapper.writeValueAsString(Map.of(
                    "headline", c.headline() == null ? "" : c.headline(),
                    "type", c.type() == null ? "" : c.type(),
                    "detail", c.detail() == null ? "" : c.detail(),
                    "summaryId", summaryId
            ));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("failed to serialize confirmation payload", e);
        }
    }
}
