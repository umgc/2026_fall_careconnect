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
    private static final int TOKEN_REFRESH_MAX_ATTEMPTS = 3;
    /** Short backoff keeps unit tests fast while still spacing retries. */
    private static final long TOKEN_REFRESH_BACKOFF_MS = 25L;

    private final RestTemplate http;
    private final EmailCredentialRepository credRepo;
    private final TokenCryptor tokenCryptor;
    private final EmailCredentialLifecycleService credentialLifecycle;

    @Value("${google.oauth.client-id:${spring.security.oauth2.client.registration.google.client-id:}}")
    String clientId;

    @Value("${google.oauth.client-secret:${spring.security.oauth2.client.registration.google.client-secret:}}")
    String clientSecret;

    @Value("${google.oauth.redirect-uri:}")
    String redirectUri;

    public void exchange(String userId, String code) {
        exchange(userId, code, EmailCredential.Provider.GMAIL, redirectUri);
    }

    public void exchange(String userId, String code, EmailCredential.Provider provider, String redirectUriOverride) {
        String effectiveRedirectUri = (redirectUriOverride == null || redirectUriOverride.isBlank())
                ? redirectUri
                : redirectUriOverride;

        if (clientId == null || clientId.isBlank() ||
            clientSecret == null || clientSecret.isBlank() ||
            effectiveRedirectUri == null || effectiveRedirectUri.isBlank()) {

            throw new IllegalStateException(
                "Google OAuth not configured (missing clientId/clientSecret/redirectUri)"
            );
        }

        try {
            System.out.println("[GoogleOAuth] Starting token exchange for userId: " + userId);
            System.out.println("[GoogleOAuth] Using clientId: " + safeId(clientId));
            System.out.println("[GoogleOAuth] Using redirectUri: " + effectiveRedirectUri);

            GoogleTokenResponse token = postForToken(formForAuthCode(code, effectiveRedirectUri));

            System.out.println("[GoogleOAuth] Token response received: " + (token != null ? "yes" : "null"));
            if (token == null || token.accessToken() == null) {
                throw new IllegalStateException("Google token exchange failed - no access token received");
            }

            System.out.println("[GoogleOAuth] Access token received, creating EmailCredential");

            EmailCredential ec = new EmailCredential();
            ec.setUserId(userId);
            ec.setProvider(provider);
            ec.setAccessTokenEnc(tokenCryptor.encrypt(token.accessToken()));

            if (token.refreshToken() != null) {
                System.out.println("[GoogleOAuth] Refresh token present, encrypting");
                ec.setRefreshTokenEnc(tokenCryptor.encrypt(token.refreshToken()));
            } else {
                System.out.println("[GoogleOAuth] No refresh token, checking for existing one");
                // keep last refresh token if Google omitted it on a subsequent grant
                Optional.ofNullable(
                        credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, provider)
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
     * Refresh access token when near expiry. Halts sync only on auth-revocation
     * signals from the token endpoint ({@code invalid_grant}, HTTP 401). Transient
     * failures (429 / 5xx) are retried with backoff and do not set NEEDS_REAUTH.
     * Gmail API 401/403 Ã¢â€ â€™ halt remains in {@link GmailClient}.
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

        final MultiValueMap<String, String> refreshForm = formForRefresh(refresh);
        HttpStatusCodeException lastTransient = null;
        for (int attempt = 1; attempt <= TOKEN_REFRESH_MAX_ATTEMPTS; attempt++) {
            try {
                GoogleTokenResponse token = postForToken(refreshForm);

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
                if (isAuthRevocationSignal(ex)) {
                    haltOnTokenRevocation(current, ex);
                }
                if (!isTransientTokenHttpError(ex) || attempt == TOKEN_REFRESH_MAX_ATTEMPTS) {
                    throw new IllegalStateException(
                            "Google token refresh temporarily unavailable ("
                                    + ex.getStatusCode().value() + ")",
                            ex);
                }
                lastTransient = ex;
                sleepBeforeTokenRetry(attempt);
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
        throw new IllegalStateException(
                "Google token refresh temporarily unavailable",
                lastTransient);
    }

    private void haltOnTokenRevocation(
            final EmailCredential current, final HttpStatusCodeException ex) {
        final String body = ex.getResponseBodyAsString();
        final String reason = "Google token refresh rejected (" + ex.getStatusCode().value() + ")"
                + (body == null || body.isBlank() ? "" : ": " + body);
        credentialLifecycle.markNeedsReauth(current, reason);
        throw new EmailCredentialNeedsReauthException(
                current.getUserId(),
                "Gmail access was revoked or expired. Reconnect to resume mail sync.",
                EmailCredentialLifecycleService.RECONNECT_PATH);
    }

    /**
     * Token-endpoint auth revocation: {@code invalid_grant} body and/or HTTP 401.
     * Non-{@code invalid_grant} 400s are not treated as revocation.
     */
    static boolean isAuthRevocationSignal(final HttpStatusCodeException ex) {
        if (ex == null) {
            return false;
        }
        if (ex.getStatusCode().value() == 401) {
            return true;
        }
        final String body = ex.getResponseBodyAsString();
        return body != null && body.toLowerCase().contains("invalid_grant");
    }

    static boolean isTransientTokenHttpError(final HttpStatusCodeException ex) {
        if (ex == null) {
            return false;
        }
        final int status = ex.getStatusCode().value();
        return status == 429 || ex.getStatusCode().is5xxServerError();
    }

    private void sleepBeforeTokenRetry(final int attempt) {
        try {
            Thread.sleep(TOKEN_REFRESH_BACKOFF_MS * (long) attempt);
        } catch (final InterruptedException ie) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted during Google token refresh backoff", ie);
        }
    }

    public Optional<EmailCredential> findLatestCredential(String userId, EmailCredential.Provider provider) {
        return credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, provider);
    }

    public void disconnect(String userId, EmailCredential.Provider provider) {
        findLatestCredential(userId, provider).ifPresent(credRepo::delete);
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

    private MultiValueMap<String, String> formForAuthCode(String code, String effectiveRedirectUri) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("code", code);
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("redirect_uri", effectiveRedirectUri);
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

    /**
     * Best-effort Google token revoke used when the user explicitly disconnects.
     * Local credential deletion still proceeds even if revoke fails.
     */
    public void revokeIfPossible(EmailCredential credential) {
        if (credential == null) {
            return;
        }
        try {
            String refreshEnc = credential.getRefreshTokenEnc();
            if (refreshEnc != null && !refreshEnc.isBlank()) {
                String refresh = tokenCryptor.decrypt(refreshEnc);
                if (refresh != null && !refresh.isBlank()) {
                    MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
                    form.add("token", refresh);
                    HttpHeaders headers = new HttpHeaders();
                    headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
                    http.postForEntity(
                            "https://oauth2.googleapis.com/revoke",
                            new HttpEntity<>(form, headers),
                            String.class);
                }
            }
        } catch (Exception ignored) {
            // Best-effort revoke; local deletion still removes app access.
        }
    }
}
