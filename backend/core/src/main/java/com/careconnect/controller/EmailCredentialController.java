package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.User;
import com.careconnect.model.EmailCredential;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialLifecycleService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping({"/api/email-credentials", "/v1/api/email-credentials"})
@RequiredArgsConstructor
public class EmailCredentialController {

    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final EmailCredentialLifecycleService credentialLifecycle;

    /**
     * Legacy boolean status — true only when Gmail sync is ACTIVE.
     * Frontend historically called {@code /api/email-credentials/status}.
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/status")
    public ResponseEntity<Boolean> getConnectionStatus(@RequestParam String userId)
            throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        return ResponseEntity.ok(credentialLifecycle.isActivelyConnected(userId));
    }

    /**
     * Rich connection status including needsReconnect + reconnectPath (Task 3.14.9).
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/connection")
    public ResponseEntity<EmailConnectionStatusResponse> getConnectionDetails(
            @RequestParam String userId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(credentialLifecycle.connectionStatus(userId));
    }

    /**
     * Disconnect Gmail and halt mail sync; user can reconnect via OAuth start.
     */
    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/disconnect")
    public ResponseEntity<Map<String, Object>> disconnect(@RequestParam String userId)
            throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        EmailCredential disconnected = credentialLifecycle.disconnect(userId);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("disconnected", disconnected != null);
        body.put("status", disconnected == null ? "DISCONNECTED" : disconnected.getStatus().name());
        body.put("syncEnabled", false);
        body.put("reconnectPath", EmailCredentialLifecycleService.RECONNECT_PATH);
        return ResponseEntity.ok(body);
    }
}
