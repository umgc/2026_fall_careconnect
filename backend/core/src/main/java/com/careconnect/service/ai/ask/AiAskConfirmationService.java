package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiAskConfirmationRequest;
import com.careconnect.model.User;
import com.careconnect.model.ai.ask.AiAskConfirmationDecision;
import com.careconnect.repository.ai.ask.AiAskConfirmationDecisionRepository;
import com.careconnect.service.ai.audit.AiAskAuditService;
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
 */
@Service
public class AiAskConfirmationService {

    private static final Logger log = LoggerFactory.getLogger(AiAskConfirmationService.class);

    public static final String APPROVE_ONCE = "APPROVE_ONCE";
    public static final String APPROVE_SESSION = "APPROVE_SESSION";
    public static final String DECLINE = "DECLINE";

    private static final Set<String> ALLOWED = Set.of(APPROVE_ONCE, APPROVE_SESSION, DECLINE);

    private final AiAskConfirmationDecisionRepository decisionRepository;
    private final AiAskAuditService askAuditService;

    public AiAskConfirmationService(
            final AiAskConfirmationDecisionRepository decisionRepository,
            final AiAskAuditService askAuditService) {
        this.decisionRepository = decisionRepository;
        this.askAuditService = askAuditService;
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

    @Transactional
    public AiAskConfirmationDecision recordDecision(
            final User caller, final AiAskConfirmationRequest request) {
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
        final AiAskConfirmationDecision saved = decisionRepository.save(AiAskConfirmationDecision.builder()
                .id(UUID.randomUUID())
                .sessionId(request.sessionId())
                .patientId(request.patientId())
                .callerUserId(caller.getId())
                .requestId(request.requestId())
                .decision(decision)
                .createdAt(Instant.now())
                .build());
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

    private static String normalizeDecision(final String raw) {
        return raw.trim().toUpperCase(Locale.ROOT).replace('-', '_').replace(' ', '_');
    }
}
