package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.dto.GmailConnectUrlResponse;
import com.careconnect.security.AuthRequestSupport;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialService;
import jakarta.servlet.http.HttpServletRequest;
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
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/email-credentials")
@RequiredArgsConstructor
public class EmailCredentialController {

    private final EmailCredentialService emailCredentialService;

    @GetMapping("/status")
    public ResponseEntity<EmailConnectionStatus> getConnectionStatus(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {
        AuthRequestSupport.requireAuthenticated(jwt);
        String identifier = firstNonBlank(patientEmail, userId);
        return ResponseEntity.ok(emailCredentialService.getGmailConnectionStatus(identifier));
    }

    @DeleteMapping("/gmail")
    public ResponseEntity<Void> disconnectGmail(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {
        AuthRequestSupport.requireAuthenticated(jwt);
        String identifier = firstNonBlank(patientEmail, userId);
        emailCredentialService.disconnectGmail(identifier);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/gmail/connect-url")
    public ResponseEntity<GmailConnectUrlResponse> getGmailConnectUrl(
            @AuthenticationPrincipal Jwt jwt,
            HttpServletRequest request,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId,
            @RequestParam(required = false) String returnUrl) throws UnauthorizedException {
        AuthRequestSupport.requireAuthenticated(jwt);
        String identifier = firstNonBlank(patientEmail, userId);
        String startToken = emailCredentialService.createGmailOAuthStartToken(identifier, returnUrl);
        String url = ServletUriComponentsBuilder.fromContextPath(request)
                .path("/oauth/google/start")
                .queryParam("startToken", startToken)
                .build()
                .toUriString();
        return ResponseEntity.ok(new GmailConnectUrlResponse(url));
    }

    private static String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) return first.trim();
        if (second != null && !second.isBlank()) return second.trim();
        return null;
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
        requireCredentialOwnerAccess(userId);
        return ResponseEntity.ok(credentialLifecycle.isActivelyConnected(userId));
    }

    /**
     * Rich connection status including needsReconnect + reconnectPath (Task 3.14.9).
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/connection")
    public ResponseEntity<EmailConnectionStatusResponse> getConnectionDetails(
            @RequestParam String userId) throws UnauthorizedException {
        requireCredentialOwnerAccess(userId);
        return ResponseEntity.ok(credentialLifecycle.connectionStatus(userId));
    }

    /**
     * Disconnect Gmail and halt mail sync; user can reconnect via OAuth start.
     */
    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/disconnect")
    public ResponseEntity<Map<String, Object>> disconnect(@RequestParam String userId)
            throws UnauthorizedException {
        requireCredentialOwnerAccess(userId);

        EmailCredential disconnected = credentialLifecycle.disconnect(userId);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("disconnected", disconnected != null);
        body.put("status", disconnected == null ? "DISCONNECTED" : disconnected.getStatus().name());
        body.put("syncEnabled", false);
        body.put("reconnectPath", EmailCredentialLifecycleService.RECONNECT_PATH);
        return ResponseEntity.ok(body);
    }

    /**
     * Caregivers may only inspect/disconnect their own Gmail credential; admins may
     * act on any userId. Prevents cross-user lastError reads and forced disconnects.
     */
    private void requireCredentialOwnerAccess(final String userId) throws UnauthorizedException {
        final User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        try {
            authorizationService.requireSelfOrAdmin(currentUser, Long.parseLong(userId));
        } catch (final NumberFormatException ex) {
            throw new UnauthorizedException("Invalid userId");
        }
    }
}
