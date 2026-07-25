package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.dto.EmailValidateRequest;
import com.careconnect.dto.ImapConnectRequest;
import com.careconnect.email.EmailDomainDetector;
import com.careconnect.email.EmailProvider;
import com.careconnect.email.EmailProviderRouter;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailAddressValidationService;
import com.careconnect.service.EmailCredentialLifecycleService;
import com.careconnect.service.ImapEmailCredentialService;
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
    private final EmailAddressValidationService validationService;
    private final EmailProviderRouter providerRouter;
    private final EmailDomainDetector domainDetector;
    private final ImapEmailCredentialService imapEmailCredentialService;

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/status")
    public ResponseEntity<Boolean> getConnectionStatus(@RequestParam String userId)
            throws UnauthorizedException {
        requireCredentialOwnerAccess(userId);
        return ResponseEntity.ok(credentialLifecycle.isActivelyConnected(userId));
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/connection")
    public ResponseEntity<EmailConnectionStatusResponse> getConnectionDetails(
            @RequestParam String userId) throws UnauthorizedException {
        requireCredentialOwnerAccess(userId);
        return ResponseEntity.ok(credentialLifecycle.connectionStatus(userId));
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @PostMapping("/validate")
    public ResponseEntity<Map<String, Object>> validate(@RequestBody EmailValidateRequest request)
            throws UnauthorizedException {
        securityUtil.resolveCurrentUser();
        final var result = validationService.validate(request.email(), request.smtpProbe());
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("valid", result.valid());
        body.put("error", result.error());
        body.put("domain", result.domain());
        body.put("mxValid", result.mxValid());
        body.put("smtpAccepted", result.smtpAccepted());
        if (result.valid()) {
            final EmailCredential.Provider provider = domainDetector.detectProvider(request.email());
            final EmailProvider.AuthMode authMode = domainDetector.authModeFor(provider);
            body.put("provider", provider.name());
            body.put("authMode", authMode.name());
            body.put("reconnectPath", domainDetector.reconnectPathFor(provider));
            body.put("defaultImapHost", domainDetector.defaultImapHost(provider, request.email()));
        }
        return ResponseEntity.ok(body);
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/connect-url")
    public ResponseEntity<Map<String, Object>> connectUrl(
            @RequestParam String userId,
            @RequestParam String email,
            @RequestParam(required = false) String returnUrl) throws UnauthorizedException {
        requireCredentialOwnerAccess(userId);
        final var result = validationService.validate(email, false);
        if (!result.valid()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "valid", false,
                    "error", result.error() == null ? "Invalid email" : result.error()));
        }
        final EmailCredential.Provider provider = domainDetector.detectProvider(email);
        final EmailProvider.AuthMode authMode = domainDetector.authModeFor(provider);
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("provider", provider.name());
        body.put("authMode", authMode.name());
        body.put("reconnectPath", domainDetector.reconnectPathFor(provider));
        body.put("email", email.trim());
        if (authMode == EmailProvider.AuthMode.OAUTH) {
            final String path = domainDetector.reconnectPathFor(provider);
            String url = path + "?userId=" + userId;
            if (returnUrl != null && !returnUrl.isBlank()) {
                url += "&returnUrl=" + java.net.URLEncoder.encode(returnUrl, java.nio.charset.StandardCharsets.UTF_8);
            }
            body.put("oauthStartPath", url);
        } else {
            body.put("imapHost", domainDetector.defaultImapHost(provider, email));
            body.put("imapPort", 993);
        }
        return ResponseEntity.ok(body);
    }

    @RequirePermission(Permission.RECORD_HEALTH_DATA)
    @PostMapping("/imap/connect")
    public ResponseEntity<EmailConnectionStatusResponse> connectImap(@RequestBody ImapConnectRequest request)
            throws UnauthorizedException {
        requireCredentialOwnerAccess(request.userId());
        imapEmailCredentialService.connect(request);
        return ResponseEntity.ok(credentialLifecycle.connectionStatus(request.userId()));
    }

    @RequirePermission(Permission.RECORD_HEALTH_DATA)
    @PostMapping("/disconnect")
    public ResponseEntity<Map<String, Object>> disconnect(@RequestParam String userId)
            throws UnauthorizedException {
        requireCredentialOwnerAccess(userId);

        EmailCredential disconnected = credentialLifecycle.disconnect(userId);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("disconnected", disconnected != null);
        body.put("status", disconnected == null ? "DISCONNECTED" : disconnected.getStatus().name());
        body.put("syncEnabled", false);
        body.put("reconnectPath", disconnected == null
                ? EmailCredentialLifecycleService.RECONNECT_PATH
                : domainDetector.reconnectPathFor(disconnected.getProvider()));
        return ResponseEntity.ok(body);
    }

    /**
     * Patient, caregiver, or admin may manage their own mailbox credentials.
     */
    private void requireCredentialOwnerAccess(final String userId) throws UnauthorizedException {
        final User currentUser = securityUtil.resolveCurrentUser();
        try {
            authorizationService.requireSelfOrAdmin(currentUser, Long.parseLong(userId));
        } catch (final NumberFormatException ex) {
            throw new UnauthorizedException("Invalid userId");
        }
    }
}
