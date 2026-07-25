package com.careconnect.service;

import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.email.EmailDomainDetector;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.security.TokenCryptor;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.Map;

/**
 * Microsoft identity platform OAuth for Outlook / Hotmail / Live mailboxes.
 */
@Service
@RequiredArgsConstructor
public class MicrosoftOAuthService {

    private static final String TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token";

    private final RestTemplate http;
    private final EmailCredentialRepository credRepo;
    private final TokenCryptor tokenCryptor;
    private final EmailCredentialLifecycleService credentialLifecycle;
    private final EmailDomainDetector domainDetector;

    @Value("${microsoft.oauth.client-id:}")
    String clientId;

    @Value("${microsoft.oauth.client-secret:}")
    String clientSecret;

    @Value("${microsoft.oauth.redirect-uri:}")
    String redirectUri;

    @Value("${microsoft.oauth.scope:openid offline_access https://graph.microsoft.com/Mail.Read}")
    String scope;

    public void exchange(final String userId, final String code) {
        if (clientId == null || clientId.isBlank()
                || clientSecret == null || clientSecret.isBlank()
                || redirectUri == null || redirectUri.isBlank()) {
            throw new IllegalStateException(
                    "Microsoft OAuth not configured (missing clientId/clientSecret/redirectUri)");
        }

        final MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("code", code);
        form.add("redirect_uri", redirectUri);
        form.add("grant_type", "authorization_code");
        form.add("scope", scope);

        final HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        final ResponseEntity<Map> response = http.exchange(
                TOKEN_URL, HttpMethod.POST, new HttpEntity<>(form, headers), Map.class);
        final Map body = response.getBody();
        if (body == null || body.get("access_token") == null) {
            throw new IllegalStateException("Microsoft token exchange failed");
        }

        final EmailCredential ec = new EmailCredential();
        ec.setUserId(userId);
        ec.setProvider(EmailCredential.Provider.OUTLOOK);
        ec.setAuthMode(EmailCredential.AuthMode.OAUTH);
        ec.setAccessTokenEnc(tokenCryptor.encrypt(String.valueOf(body.get("access_token"))));
        if (body.get("refresh_token") != null) {
            ec.setRefreshTokenEnc(tokenCryptor.encrypt(String.valueOf(body.get("refresh_token"))));
        } else {
            credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.OUTLOOK)
                    .map(EmailCredential::getRefreshTokenEnc)
                    .ifPresent(ec::setRefreshTokenEnc);
        }
        final Object expiresIn = body.get("expires_in");
        if (expiresIn != null) {
            ec.setExpiresAt(Instant.now().plusSeconds(Long.parseLong(String.valueOf(expiresIn))));
        }
        ec.setStatus(EmailCredential.Status.ACTIVE);
        ec.setSyncEnabled(true);
        final EmailCredential saved = credRepo.save(ec);
        credentialLifecycle.activateAfterConnect(saved);
    }

    public EmailCredential ensureFreshToken(final EmailCredential current) {
        if (current == null) {
            return null;
        }
        if (current.getExpiresAt() != null && current.getExpiresAt().isAfter(Instant.now().plusSeconds(60))) {
            return current;
        }
        if (current.getRefreshTokenEnc() == null || current.getRefreshTokenEnc().isBlank()) {
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    "Missing Microsoft refresh token",
                    domainDetector.reconnectPathFor(EmailCredential.Provider.OUTLOOK));
        }
        try {
            final MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
            form.add("client_id", clientId);
            form.add("client_secret", clientSecret);
            form.add("refresh_token", tokenCryptor.decrypt(current.getRefreshTokenEnc()));
            form.add("grant_type", "refresh_token");
            form.add("scope", scope);
            final HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
            final ResponseEntity<Map> response = http.exchange(
                    TOKEN_URL, HttpMethod.POST, new HttpEntity<>(form, headers), Map.class);
            final Map body = response.getBody();
            if (body == null || body.get("access_token") == null) {
                throw new IllegalStateException("Microsoft refresh failed");
            }
            current.setAccessTokenEnc(tokenCryptor.encrypt(String.valueOf(body.get("access_token"))));
            if (body.get("refresh_token") != null) {
                current.setRefreshTokenEnc(tokenCryptor.encrypt(String.valueOf(body.get("refresh_token"))));
            }
            final Object expiresIn = body.get("expires_in");
            if (expiresIn != null) {
                current.setExpiresAt(Instant.now().plusSeconds(Long.parseLong(String.valueOf(expiresIn))));
            }
            return credentialLifecycle.activateAfterConnect(credRepo.save(current));
        } catch (final HttpStatusCodeException | IllegalStateException ex) {
            credentialLifecycle.markNeedsReauth(current, ex.getMessage());
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    ex.getMessage(),
                    domainDetector.reconnectPathFor(EmailCredential.Provider.OUTLOOK));
        }
    }
}
