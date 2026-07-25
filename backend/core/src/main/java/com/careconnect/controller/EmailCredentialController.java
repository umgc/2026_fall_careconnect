package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.dto.EmailValidateRequest;
import com.careconnect.dto.ImapConnectRequest;
import com.careconnect.email.EmailDomainDetector;
import com.careconnect.email.EmailProvider;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.OAuthRedirectValidator;
import com.careconnect.security.OAuthStateSigner;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailAddressValidationService;
import com.careconnect.service.EmailCredentialLifecycleService;
import com.careconnect.service.ImapEmailCredentialService;
import com.careconnect.util.SecurityUtil;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

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
    private final EmailDomainDetector domainDetector;
    private final ImapEmailCredentialService imapEmailCredentialService;
    private final OAuthStateSigner oauthStateSigner;
    private final OAuthRedirectValidator oauthRedirectValidator;

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

    /**
     * Builds a provider connect payload. OAuth providers receive a signed
     * {@code startToken} URL — {@code userId} is taken from the authenticated
     * principal (admins may target another user via {@code userId} after self-or-admin check).
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/connect-url")
    public ResponseEntity<Map<String, Object>> connectUrl(
            HttpServletRequest request,
            @RequestParam(required = false) String userId,
            @RequestParam String email,
            @RequestParam(required = false) String returnUrl) throws UnauthorizedException {
        final String resolvedUserId = resolveCredentialUserId(userId);
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
            final String sanitizedReturn = oauthRedirectValidator.sanitizeReturnUrl(returnUrl);
            final String startToken = oauthStateSigner.signStartToken(resolvedUserId, sanitizedReturn);
            final String path = domainDetector.reconnectPathFor(provider);
            final String url = ServletUriComponentsBuilder.fromContextPath(request)
                    .path(path.startsWith("/") ? path : "/" + path)
                    .queryParam("startToken", startToken)
                    .build()
                    .toUriString();
            body.put("oauthStartPath", url);
            body.put("startToken", startToken);
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
        final String resolvedUserId = resolveCredentialUserId(request.userId());
        final ImapConnectRequest scoped = new ImapConnectRequest(
                resolvedUserId,
                request.email(),
                request.appPassword(),
                request.imapHost(),
                request.imapPort());
        imapEmailCredentialService.connect(scoped);
        return ResponseEntity.ok(credentialLifecycle.connectionStatus(resolvedUserId));
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
     * When {@code userId} is omitted, the authenticated principal is used.
     */
    private String resolveCredentialUserId(final String userId) throws UnauthorizedException {
        final User currentUser = securityUtil.resolveCurrentUser();
        if (userId == null || userId.isBlank()) {
            return String.valueOf(currentUser.getId());
        }
        requireCredentialOwnerAccess(userId);
        return userId.trim();
    }

    private void requireCredentialOwnerAccess(final String userId) throws UnauthorizedException {
        final User currentUser = securityUtil.resolveCurrentUser();
        try {
            authorizationService.requireSelfOrAdmin(currentUser, Long.parseLong(userId));
        } catch (final NumberFormatException ex) {
            throw new UnauthorizedException("Invalid userId");
        }
    }
}
