package com.careconnect.controller;

import com.careconnect.security.OAuthRedirectValidator;
import com.careconnect.service.GoogleOAuthService;
import com.careconnect.security.OAuthStateSigner;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.util.UriComponentsBuilder;
import org.springframework.web.util.UriUtils;

import java.net.URI;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/oauth")
@RequiredArgsConstructor
@Slf4j
public class EmailOAuthController {

    /** Query param read by {@code usps_test_screen._handleOAuthReturnError()} (also accepts legacy {@code error}). */
    static final String OAUTH_ERROR_PARAM = "oauthError";
    private static final String OAUTH_ERROR_CODE = "oauth_failed";

    private final GoogleOAuthService googleOAuthService;
    private final OAuthStateSigner oauthStateSigner;
    private final OAuthRedirectValidator oauthRedirectValidator;

    @Value("${google.oauth.client-id:}")    String clientId;
    @Value("${google.oauth.redirect-uri:}") String redirectUri;
    @Value("${google.oauth.scope:email}")   String scope;
    @Value("${google.oauth.frontend-url:http://localhost}") String frontendBaseUrl;

    /**
     * Public entry for external browsers. Requires a short-lived {@code startToken}
     * from {@code GET /v1/api/email-credentials/gmail/connect-url} (JWT-authenticated).
     */
    @GetMapping("/google/start")
    public ResponseEntity<Void> start(@RequestParam String startToken) {
        OAuthStateSigner.ParsedOAuthState startData = oauthStateSigner.verifyStartToken(startToken);
        String signedState = oauthStateSigner.sign(startData.userId(), startData.returnUrl());

        String authUrl = UriComponentsBuilder
                .fromHttpUrl("https://accounts.google.com/o/oauth2/v2/auth")
                .queryParam("response_type", "code")
                .queryParam("client_id", clientId)
                .queryParam("redirect_uri", UriUtils.encode(redirectUri, StandardCharsets.UTF_8))
                .queryParam("scope", UriUtils.encode(scope, StandardCharsets.UTF_8))
                .queryParam("access_type", "offline")
                .queryParam("prompt", "consent")
                .queryParam("state", UriUtils.encode(signedState, StandardCharsets.UTF_8))
                .build(true)
                .toUriString();

        return ResponseEntity.status(302).location(URI.create(authUrl)).build();
    }

    @GetMapping("/google/callback")
    public ResponseEntity<Void> callback(@RequestParam String code, @RequestParam String state) {
        String returnUrl = null;
        try {
            OAuthStateSigner.ParsedOAuthState stateData = oauthStateSigner.verify(state);
            returnUrl = stateData.returnUrl();
            googleOAuthService.exchange(stateData.userId(), code);
            return ResponseEntity.status(302).location(URI.create(resolveSuccessRedirect(returnUrl))).build();
        } catch (Exception e) {
            return ResponseEntity.status(302).location(URI.create(buildOAuthErrorRedirect(returnUrl, e))).build();
        }
    }

    private String resolveSuccessRedirect(String returnUrl) {
        return oauthRedirectValidator.resolveRedirect(returnUrl, frontendBaseUrl);
    }

    private String buildOAuthErrorRedirect(String returnUrl, Exception e) {
        String base = resolveSuccessRedirect(returnUrl);
        log.warn("Gmail OAuth callback failed", e);
        String separator = base.contains("?") ? "&" : "?";
        return base + separator + OAUTH_ERROR_PARAM + "=" + OAUTH_ERROR_CODE;
    }
}
