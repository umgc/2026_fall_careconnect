package com.careconnect.controller;

import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.AiAskResponse;
import com.careconnect.model.User;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.ask.AskAiException;
import com.careconnect.service.ai.ask.AiAskConfirmationService;
import com.careconnect.service.ai.ask.AiAskService;
import com.careconnect.service.ai.ask.AskAiRejectedException;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.util.SecurityUtil;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Task 5.3 — records-grounded Ask AI gateway ({@code POST /api/ai/ask}).
 *
 * <p>Caller is resolved from JWT. Patient access and source-type RBAC are enforced by
 * {@link com.careconnect.service.ai.retrieval.RetrievalScopeService}.
 *
 * <p>All failure modes return {@link AiAskResponse} with {@code deliveryStatus=WITHHELD}
 * (including {@link ForbiddenScopeException}) so clients share one error contract.
 */
@Slf4j
@RestController
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.ai.ask.enabled", havingValue = "true", matchIfMissing = true)
@RequestMapping({"/api/ai", "/v1/api/ai"})
public class AiAskController {

    private final AiAskService aiAskService;
    private final AiAskConfirmationService askConfirmationService;
    private final SecurityUtil securityUtil;

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping(
            value = "/ask",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<AiAskResponse> ask(@Valid @RequestBody final AiAskRequest request)
            throws UnauthorizedException {
        final java.util.UUID sessionId = request == null ? null : request.sessionId();
        try {
            final User caller = securityUtil.resolveCurrentUser();
            final AiAskResponse response = aiAskService.ask(caller, request);
            return ResponseEntity.ok(response);
        } catch (final ForbiddenScopeException ex) {
            log.warn(
                    "Ask AI forbidden scope reason={} auditId={} requestId={}",
                    ex.getDenialReason(),
                    ex.getAuditId(),
                    ex.getRequestId());
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(AiAskService.withheld(
                            ex.getRequestId(),
                            ex.getAuditId(),
                            ex.getSessionId() == null ? sessionId : ex.getSessionId(),
                            ForbiddenScopeException.ERROR_CODE,
                            "Requested records are not available for Ask AI",
                            null));
        } catch (final AskAiRejectedException ex) {
            log.warn("Ask AI rejected code={}", ex.getErrorCode());
            return ResponseEntity.status(ex.getHttpStatus())
                    .body(AiAskService.withheld(
                            ex.getRequestId(),
                            ex.getAuditId(),
                            ex.getSessionId() == null ? sessionId : ex.getSessionId(),
                            ex.getErrorCode(), ex.getMessage(), null));
        } catch (final AskAiException ex) {
            log.warn("Ask AI failed code={} requestId={}", ex.getErrorCode(), ex.getRequestId());
            return ResponseEntity.status(ex.getStatus())
                    .body(AiAskService.withheld(
                            ex.getRequestId(),
                            ex.getAuditId(),
                            ex.getSessionId() == null ? sessionId : ex.getSessionId(),
                            ex.getErrorCode(), ex.getMessage(), null));
        } catch (final RuntimeException ex) {
            final java.util.UUID requestId = java.util.UUID.randomUUID();
            final java.util.UUID auditId = java.util.UUID.randomUUID();
            // Never log exception messages or request data: either may contain PHI.
            log.error(
                    "Ask AI unexpected pipeline failure requestId={} auditId={} type={}",
                    requestId,
                    auditId,
                    ex.getClass().getSimpleName());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(AiAskService.withheld(
                            requestId,
                            auditId,
                            sessionId,
                            "INTERNAL_ERROR",
                            "Ask AI could not complete the request",
                            null));
        }
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping(
            value = "/ask/confirmation",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> confirm(
            @Valid @RequestBody final com.careconnect.dto.ai.AiAskConfirmationRequest request)
            throws UnauthorizedException {
        final User caller = securityUtil.resolveCurrentUser();
        try {
            final var saved = askConfirmationService.recordDecision(caller, request);
            return ResponseEntity.ok(java.util.Map.of(
                    "success", true,
                    "decision", saved.getDecision(),
                    "sessionId", saved.getSessionId().toString(),
                    "createdAt", saved.getCreatedAt().toString()));
        } catch (final IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(java.util.Map.of(
                    "success", false,
                    "error", ex.getMessage() == null ? "Invalid confirmation request" : ex.getMessage()));
        }
    }
}
