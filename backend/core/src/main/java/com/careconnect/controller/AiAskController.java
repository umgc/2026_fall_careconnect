package com.careconnect.controller;

import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.AiAskResponse;
import com.careconnect.model.User;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.ask.AiAskService;
import com.careconnect.service.ai.ask.AskAiRejectedException;
import com.careconnect.service.ai.ask.AskAiUnavailableException;
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
    private final SecurityUtil securityUtil;

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping(
            value = "/ask",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<AiAskResponse> ask(@Valid @RequestBody final AiAskRequest request)
            throws UnauthorizedException {
        final User caller = securityUtil.resolveCurrentUser();
        final java.util.UUID sessionId = request == null ? null : request.sessionId();
        try {
            final AiAskResponse response = aiAskService.ask(caller, request);
            return ResponseEntity.ok(response);
        } catch (final ForbiddenScopeException ex) {
            log.warn("Ask AI forbidden scope code={} msg={}", ex.getErrorCode(), ex.getMessage());
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(AiAskService.withheld(
                            null,
                            ex.getAuditId(),
                            sessionId,
                            ForbiddenScopeException.ERROR_CODE,
                            ex.getMessage(),
                            null));
        } catch (final AskAiRejectedException ex) {
            log.warn("Ask AI rejected code={} msg={}", ex.getErrorCode(), ex.getMessage());
            return ResponseEntity.status(ex.getHttpStatus())
                    .body(AiAskService.withheld(
                            null, null, sessionId,
                            ex.getErrorCode(), ex.getMessage(), null));
        } catch (final AskAiUnavailableException ex) {
            log.warn("Ask AI unavailable: {}", ex.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(AiAskService.withheld(
                            null, null, sessionId,
                            ex.getErrorCode(), ex.getMessage(), null));
        }
    }
}
