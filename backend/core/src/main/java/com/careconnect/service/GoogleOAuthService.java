package com.careconnect.service;

import com.careconnect.dto.GoogleTokenResponse;
import com.careconnect.exception.EmailCredentialNeedsReauthException;
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
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class GoogleOAuthService {

    private static final String TOKEN_URL = "https://oauth2.googleapis.com/token";

    private final RestTemplate http;
    private final EmailCredentialRepository credRepo;
    private final TokenCryptor tokenCryptor;
    private final EmailCredentialLifecycleService credentialLifecycle;

    @Value("${google.oauth.client-id:}")
    String clientId;

    @Value("${google.oauth.client-secret:}")
    String clientSecret;

    @Value("${google.oauth.redirect-uri:}")
    String redirectUri;

    public void exchange(String userId, String code) {

        if (clientId == null || clientId.isBlank() ||
            clientSecret == null || clientSecret.isBlank() ||
            redirectUri == null || redirectUri.isBlank()) {

            throw new IllegalStateException(
                "Google OAuth not configured (missing clientId/clientSecret/redirectUri)"
            );
        }

        try {
            System.out.println("[GoogleOAuth] Starting token exchange for userId: " + userId);
            System.out.println("[GoogleOAuth] Using clientId: " + safeId(clientId));
            System.out.println("[GoogleOAuth] Using redirectUri: " + redirectUri);

            GoogleTokenResponse token = postForToken(formForAuthCode(code));

            System.out.println("[GoogleOAuth] Token response received: " + (token != null ? "yes" : "null"));
            if (token == null || token.accessToken() == null) {
                throw new IllegalStateException("Google token exchange failed - no access token received");
            }

            System.out.println("[GoogleOAuth] Access token received, creating EmailCredential");

            EmailCredential ec = new EmailCredential();
            ec.setUserId(userId);
            ec.setProvider(EmailCredential.Provider.GMAIL);
            ec.setAccessTokenEnc(tokenCryptor.encrypt(token.accessToken()));

            if (token.refreshToken() != null) {
                System.out.println("[GoogleOAuth] Refresh token present, encrypting");
                ec.setRefreshTokenEnc(tokenCryptor.encrypt(token.refreshToken()));
            } else {
                System.out.println("[GoogleOAuth] No refresh token, checking for existing one");
                // keep last refresh token if Google omitted it on a subsequent grant
                Optional.ofNullable(
                        credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL)
                                .map(EmailCredential::getRefreshTokenEnc)
                                .orElse(null)
                ).ifPresent(ec::setRefreshTokenEnc);
            }

            Instant exp = token.computeExpiryFromNow();
            ec.setExpiresAt(exp);
            ec.setStatus(EmailCredential.Status.ACTIVE);
            ec.setSyncEnabled(true);
            ec.setLastError(null);
            ec.setLastErrorAt(null);
            ec.setReauthNotifiedAt(null);
            System.out.println("[GoogleOAuth] Token expires at: " + exp);

            System.out.println("[GoogleOAuth] Saving EmailCredential to database");
            EmailCredential saved = credRepo.save(ec);
            credentialLifecycle.activateAfterConnect(saved);
            System.out.println("[GoogleOAuth] Token exchange completed successfully");

        } catch (Exception e) {
            System.err.println("[GoogleOAuth] Token exchange failed: " + e.getMessage());
            e.printStackTrace();
            throw new RuntimeException("Google OAuth token exchange failed: " + e.getMessage(), e);
        }
    }

    /**
     * Refresh access token when near expiry. On {@code invalid_grant} / 4xx from Google,
     * halts sync and signals reconnect.
     */
    public EmailCredential ensureFreshToken(EmailCredential current) {
        if (current == null) {
            return null;
        }
        if (!credentialLifecycle.allowsSync(current)) {
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    current.getLastError() != null
                            ? current.getLastError()
                            : "Gmail access revoked or expired. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        }
        if (current.getExpiresAt() != null &&
                current.getExpiresAt().isAfter(Instant.now().plusSeconds(120))) {
            return current; // still fresh
        }

        String refreshEnc = current.getRefreshTokenEnc();
        if (refreshEnc == null || refreshEnc.isBlank()) {
            credentialLifecycle.markNeedsReauth(current, "Missing refresh token");
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    "Gmail refresh token missing. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        }

        String refresh = tokenCryptor.decrypt(refreshEnc);
        if (refresh == null || refresh.isBlank()) {
            credentialLifecycle.markNeedsReauth(current, "Unable to decrypt refresh token");
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    "Gmail credentials unreadable. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        }

        try {
            GoogleTokenResponse token = postForToken(formForRefresh(refresh));

            if (token != null && token.accessToken() != null) {
                current.setAccessTokenEnc(tokenCryptor.encrypt(token.accessToken()));
                current.setExpiresAt(token.computeExpiryFromNow());
                current.setStatus(EmailCredential.Status.ACTIVE);
                current.setSyncEnabled(true);
                credRepo.save(current);
                return current;
            }

            credentialLifecycle.markNeedsReauth(current, "Google token refresh returned no access token");
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    "Gmail token refresh failed. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        } catch (EmailCredentialNeedsReauthException ex) {
            throw ex;
        } catch (HttpStatusCodeException ex) {
            final String body = ex.getResponseBodyAsString();
            final String reason = "Google token refresh rejected (" + ex.getStatusCode().value() + ")"
                    + (body == null || body.isBlank() ? "" : ": " + body);
            credentialLifecycle.markNeedsReauth(current, reason);
            throw new EmailCredentialNeedsReauthException(
                    current.getUserId(),
                    "Gmail access was revoked or expired. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        } catch (RuntimeException ex) {
            if (ex.getMessage() != null && ex.getMessage().toLowerCase().contains("invalid_grant")) {
                credentialLifecycle.markNeedsReauth(current, ex.getMessage());
                throw new EmailCredentialNeedsReauthException(
                        current.getUserId(),
                        "Gmail access was revoked or expired. Reconnect to resume mail sync.",
                        EmailCredentialLifecycleService.RECONNECT_PATH);
            }
            throw ex;
        }
    }

    private GoogleTokenResponse postForToken(MultiValueMap<String, String> form) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        headers.setAccept(java.util.List.of(MediaType.APPLICATION_JSON));

        HttpEntity<MultiValueMap<String, String>> req = new HttpEntity<>(form, headers);

        ResponseEntity<GoogleTokenResponse> resp =
                http.postForEntity(TOKEN_URL, req, GoogleTokenResponse.class);

        if (resp.getStatusCode().is2xxSuccessful()) {
            return resp.getBody();
        }
        System.err.println("[GoogleOAuth] Non-2xx from token endpoint: " + resp.getStatusCode());
        return null;
    }

    private MultiValueMap<String, String> formForAuthCode(String code) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("code", code);
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("redirect_uri", redirectUri);
        form.add("grant_type", "authorization_code");
        return form;
    }

    private MultiValueMap<String, String> formForRefresh(String refreshToken) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("refresh_token", refreshToken);
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("grant_type", "refresh_token");
        return form;
    }

    private String safeId(String id) {
        if (id == null) return "null";
        return id.length() <= 12 ? id : id.substring(0, 12) + "...";
    }
}
