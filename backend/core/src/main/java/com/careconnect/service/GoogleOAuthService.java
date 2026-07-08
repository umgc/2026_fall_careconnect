package com.careconnect.service;

import com.careconnect.dto.GoogleTokenResponse;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.security.TokenCryptor;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
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
            System.out.println("[GoogleOAuth] Token expires at: " + exp);

            System.out.println("[GoogleOAuth] Saving EmailCredential to database");
            credRepo.save(ec);
            System.out.println("[GoogleOAuth] Token exchange completed successfully");

        } catch (Exception e) {
            System.err.println("[GoogleOAuth] Token exchange failed: " + e.getMessage());
            e.printStackTrace();
            throw new RuntimeException("Google OAuth token exchange failed: " + e.getMessage(), e);
        }
    }

    // refresh utility — returns true when a usable access token is available
    public boolean ensureFreshToken(EmailCredential current) {
        if (current == null) {
            return false;
        }
        if (hasUsableAccessToken(current)) {
            return true;
        }

        String refreshEnc = current.getRefreshTokenEnc();
        if (refreshEnc == null || refreshEnc.isBlank()) {
            invalidateCredential(current);
            return false;
        }

        String refresh = tokenCryptor.decrypt(refreshEnc);
        if (refresh == null || refresh.isBlank()) {
            invalidateCredential(current);
            return false;
        }

        GoogleTokenResponse token = postForToken(formForRefresh(refresh));
        if (token != null && token.accessToken() != null) {
            current.setAccessTokenEnc(tokenCryptor.encrypt(token.accessToken()));
            current.setExpiresAt(token.computeExpiryFromNow());
            credRepo.save(current);
            return true;
        }

        invalidateCredential(current);
        return false;
    }

    public boolean hasUsableAccessToken(EmailCredential credential) {
        if (credential == null || credential.getAccessTokenEnc() == null || credential.getAccessTokenEnc().isBlank()) {
            return false;
        }
        Instant expiresAt = credential.getExpiresAt();
        return expiresAt != null && expiresAt.isAfter(Instant.now().plusSeconds(120));
    }

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
                    http.postForEntity("https://oauth2.googleapis.com/revoke", new HttpEntity<>(form, headers), String.class);
                }
            }
        } catch (Exception ignored) {
            // Best-effort revoke; local deletion still removes app access.
        }
    }

    private void invalidateCredential(EmailCredential current) {
        current.setAccessTokenEnc(null);
        current.setRefreshTokenEnc(null);
        current.setExpiresAt(Instant.EPOCH);
        credRepo.save(current);
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
        // If you want stronger error handling, inspect resp.getBody() for error and throw.
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
