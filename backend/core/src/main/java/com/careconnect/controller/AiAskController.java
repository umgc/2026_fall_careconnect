package com.careconnect.controller;

import com.careconnect.ai.ask.dto.AiAskRequest;
import com.careconnect.ai.ask.dto.AiAskResponse;
import com.careconnect.model.User;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.AiAskOrchestrator;
import com.careconnect.service.ai.AiAskOrchestrator.AiAskResult;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Slf4j
@RestController
@RequestMapping("/api/ai/ask")
@RequiredArgsConstructor
public class AiAskController {

    private final AiAskOrchestrator aiAskOrchestrator;

    @PostMapping("/{patientId}")
    public ResponseEntity<AiAskResponse> ask(
            @PathVariable Long patientId,
            @Valid @RequestBody AiAskRequest request,
            @AuthenticationPrincipal User caller) {

        log.info("POST /api/ai/ask/{} — caller={}", patientId, caller.getId());

        try {
            AiAskResult result = aiAskOrchestrator.ask(caller, patientId, request.getQuestion());
            return ResponseEntity.ok(new AiAskResponse(result.answer(), result.chunksUsed()));
        } catch (ForbiddenScopeException e) {
            log.warn("Scope denied — caller={} patientId={}", caller.getId(), patientId);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (UnauthorizedException e) {
            log.warn("Unauthorized — caller={} patientId={}", caller.getId(), patientId);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        } catch (RuntimeException e) {
            log.error("Ask AI failed for patientId={}", patientId, e);
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
    }
}