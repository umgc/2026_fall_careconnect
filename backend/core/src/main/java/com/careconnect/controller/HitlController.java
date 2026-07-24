package com.careconnect.controller;

import com.careconnect.dto.ai.hitl.HitlDetailResponse;
import com.careconnect.dto.ai.hitl.HitlQueueItem;
import com.careconnect.dto.ai.hitl.HitlRejectRequest;
import com.careconnect.dto.ai.hitl.HitlReleaseRequest;
import com.careconnect.dto.ai.hitl.HitlStatusResponse;
import com.careconnect.model.User;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.hitl.HitlConflictException;
import com.careconnect.service.ai.hitl.HitlNotFoundException;
import com.careconnect.service.ai.hitl.HitlService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Tier-2 HITL poll + reviewer release/reject APIs.
 */
@RestController
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.ai.hitl.enabled", havingValue = "true", matchIfMissing = true)
@RequestMapping({"/api/ai/hitl", "/v1/api/ai/hitl"})
public class HitlController {

    private final HitlService hitlService;
    private final SecurityUtil securityUtil;

    @RequirePermission(Permission.USE_AI_FEATURES)
    @GetMapping(value = "/{heldItemId}/status", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<HitlStatusResponse> status(@PathVariable final UUID heldItemId)
            throws UnauthorizedException {
        final User caller = securityUtil.resolveCurrentUser();
        return ResponseEntity.ok(hitlService.getStatus(heldItemId, caller));
    }

    @RequirePermission(Permission.REVIEW_AI_HOLDS)
    @GetMapping(value = "/queue", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<HitlQueueItem>> queue() throws UnauthorizedException {
        final User reviewer = securityUtil.resolveCurrentUser();
        return ResponseEntity.ok(hitlService.listQueue(reviewer));
    }

    @RequirePermission(Permission.REVIEW_AI_HOLDS)
    @GetMapping(value = "/{heldItemId}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<HitlDetailResponse> detail(@PathVariable final UUID heldItemId)
            throws UnauthorizedException {
        final User reviewer = securityUtil.resolveCurrentUser();
        return ResponseEntity.ok(hitlService.getDetail(heldItemId, reviewer));
    }

    @RequirePermission(Permission.REVIEW_AI_HOLDS)
    @PostMapping(
            value = "/{heldItemId}/release",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<HitlDetailResponse> release(
            @PathVariable final UUID heldItemId,
            @RequestBody(required = false) final HitlReleaseRequest body)
            throws UnauthorizedException {
        final User reviewer = securityUtil.resolveCurrentUser();
        final HitlReleaseRequest request = body == null ? new HitlReleaseRequest(null, null) : body;
        return ResponseEntity.ok(hitlService.release(
                heldItemId, reviewer, request.editedAnswer(), request.notes()));
    }

    @RequirePermission(Permission.REVIEW_AI_HOLDS)
    @PostMapping(
            value = "/{heldItemId}/reject",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<HitlDetailResponse> reject(
            @PathVariable final UUID heldItemId,
            @RequestBody(required = false) final HitlRejectRequest body)
            throws UnauthorizedException {
        final User reviewer = securityUtil.resolveCurrentUser();
        final HitlRejectRequest request = body == null ? new HitlRejectRequest(null) : body;
        return ResponseEntity.ok(hitlService.reject(heldItemId, reviewer, request.reason()));
    }

    @ExceptionHandler(UnauthorizedException.class)
    public ResponseEntity<Map<String, String>> forbidden(final UnauthorizedException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", "FORBIDDEN", "message", ex.getMessage()));
    }

    @ExceptionHandler(HitlNotFoundException.class)
    public ResponseEntity<Map<String, String>> notFound(final HitlNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", "NOT_FOUND", "message", ex.getMessage()));
    }

    @ExceptionHandler(HitlConflictException.class)
    public ResponseEntity<Map<String, String>> conflict(final HitlConflictException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(Map.of("error", "CONFLICT", "message", ex.getMessage()));
    }
}
