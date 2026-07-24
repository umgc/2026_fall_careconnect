package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiAskConfirmationRequest;
import com.careconnect.model.User;
import com.careconnect.model.ai.ask.AiAskConfirmationDecision;
import com.careconnect.repository.ai.ask.AiAskConfirmationDecisionRepository;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.audit.AiAskAuditService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Task 6.6 — persist Ask AI confirm-with-provider decisions (REQ-SC-5/6).
 *
 * <p>Timeout without a decision is not treated as approval.
 *
 * <p>{@link #APPROVE_SESSION} suppresses future confirmation prompts for the session.
 * {@link #APPROVE_ONCE} / {@link #DECLINE} acknowledge a specific {@code requestId}
 * (retries of that request do not re-prompt).
 */
@Service
public class AiAskConfirmationService {

    private static final Logger log = LoggerFactory.getLogger(AiAskConfirmationService.class);

    public static final String APPROVE_ONCE = "APPROVE_ONCE";
    public static final String APPROVE_SESSION = "APPROVE_SESSION";
    public static final String DECLINE = "DECLINE";

    private static final Set<String> ALLOWED = Set.of(APPROVE_ONCE, APPROVE_SESSION, DECLINE);
    private static final Set<String> REQUEST_TERMINAL =
            Set.of(APPROVE_ONCE, APPROVE_SESSION, DECLINE);

    private final AiAskConfirmationDecisionRepository decisionRepository;
    private final AiAskAuditService askAuditService;
    private final RetrievalScopeService retrievalScopeService;

    public AiAskConfirmationService(
            final AiAskConfirmationDecisionRepository decisionRepository,
            final AiAskAuditService askAuditService,
            final RetrievalScopeService retrievalScopeService) {
        this.decisionRepository = decisionRepository;
        this.askAuditService = askAuditService;
        this.retrievalScopeService = retrievalScopeService;
    }

    public boolean hasActiveSessionApproval(
            final UUID sessionId, final Long patientId, final Long callerUserId) {
        if (sessionId == null || patientId == null || callerUserId == null) {
            return false;
        }
        return decisionRepository
                .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                        sessionId, patientId, callerUserId, APPROVE_SESSION)
                .isPresent();
    }

    /**
     * True when this caller already recorded {@code decision} for {@code requestId}.
     */
    public boolean hasDecision(
            final UUID requestId, final Long callerUserId, final String decision) {
        if (requestId == null || callerUserId == null || decision == null || decision.isBlank()) {
            return false;
        }
        return decisionRepository.existsByRequestIdAndCallerUserIdAndDecision(
                requestId, callerUserId, normalizeDecision(decision));
    }

    /**
     * True when this request already has any terminal confirmation decision for the caller
     * (once / session / decline), so retries should not re-prompt.
     */
    public boolean hasTerminalDecisionForRequest(
            final UUID requestId, final Long callerUserId) {
        if (requestId == null || callerUserId == null) {
            return false;
        }
        for (final String decision : REQUEST_TERMINAL) {
            if (decisionRepository.existsByRequestIdAndCallerUserIdAndDecision(
                    requestId, callerUserId, decision)) {
                return true;
            }
        }
        return false;
    }

    @Transactional
    public AiAskConfirmationDecision recordDecision(
            final User caller, final AiAskConfirmationRequest request)
            throws ForbiddenScopeException, UnauthorizedException {
        if (caller == null || caller.getId() == null) {
            throw new IllegalArgumentException("Caller is required");
        }
        if (request == null
                || request.sessionId() == null
                || request.patientId() == null
                || request.decision() == null
                || request.decision().isBlank()) {
            throw new IllegalArgumentException("sessionId, patientId, and decision are required");
        }
        final String decision = normalizeDecision(request.decision());
        if (!ALLOWED.contains(decision)) {
            throw new IllegalArgumentException(
                    "decision must be APPROVE_ONCE, APPROVE_SESSION, or DECLINE");
        }

        // Same patient-scope gate as POST /api/ai/ask (FR-AI-1).
        retrievalScopeService.assertCanAsk(caller, request.patientId(), null);

        if (request.requestId() != null) {
            final var existing = decisionRepository
                    .findFirstByRequestIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                            request.requestId(), caller.getId(), decision);
            if (existing.isPresent()) {
                return existing.get();
            }
        }

        final AiAskConfirmationDecision saved =
                decisionRepository.save(newDecision(caller, request, decision));
        if (request.auditId() != null) {
            try {
                askAuditService.appendStandaloneEvent(
                        request.auditId(),
                        "CONFIRMATION_" + decision,
                        caller.getId(),
                        Map.of(
                                "sessionId", request.sessionId().toString(),
                                "patientId", request.patientId(),
                                "decision", decision));
            } catch (final Exception ex) {
                log.warn("Ask AI confirmation audit append failed: {}", ex.getMessage());
            }
        }
        return saved;
    }

    private static AiAskConfirmationDecision newDecision(
            final User caller,
            final AiAskConfirmationRequest request,
            final String decision) {
        return AiAskConfirmationDecision.builder()
                .id(UUID.randomUUID())
                .sessionId(request.sessionId())
                .patientId(request.patientId())
                .callerUserId(caller.getId())
                .requestId(request.requestId())
                .decision(decision)
                .createdAt(Instant.now())
                .build();
    }

    private static String normalizeDecision(final String raw) {
        return raw.trim().toUpperCase(Locale.ROOT).replace('-', '_').replace(' ', '_');
    }
}
