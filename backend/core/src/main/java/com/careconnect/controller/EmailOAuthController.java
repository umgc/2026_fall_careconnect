package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.service.GoogleOAuthService;
import com.careconnect.security.OAuthStateSigner;
import lombok.RequiredArgsConstructor;
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
public class EmailOAuthController {

    /** Query param read by {@code usps_test_screen._handleOAuthReturnError()} (also accepts legacy {@code error}). */
    static final String OAUTH_ERROR_PARAM = "oauthError";

    private final GoogleOAuthService googleOAuthService;
    private final OAuthStateSigner oauthStateSigner;

    @Value("${google.oauth.client-id:}")    String clientId;
    @Value("${google.oauth.redirect-uri:}") String redirectUri;
    @Value("${google.oauth.scope:email}")   String scope;
    @Value("${google.oauth.frontend-url:http://localhost}") String frontendBaseUrl;

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/google/start")
    public ResponseEntity<Void> start(@RequestParam String userId, @RequestParam(required = false) String returnUrl) {
        String signedState = oauthStateSigner.sign(userId, returnUrl);

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
            OAuthStateSigner.ParsedOAuthState stateData = oauthStateSigner.parse(state);
            returnUrl = stateData.returnUrl();
            googleOAuthService.exchange(stateData.userId(), code);
            return ResponseEntity.status(302).location(URI.create(resolveSuccessRedirect(returnUrl))).build();
        } catch (Exception e) {
            // All failure paths use oauthError — consumed by usps_test_screen on return from Google OAuth.
            return ResponseEntity.status(302).location(URI.create(buildOAuthErrorRedirect(returnUrl, e))).build();
        }
    }

    private String resolveSuccessRedirect(String returnUrl) {
        String frontendUrl = (returnUrl != null && !returnUrl.isEmpty())
                ? returnUrl
                : frontendBaseUrl + "/usps-test";
        try {
            new java.net.URL(frontendUrl);
            return frontendUrl;
        } catch (java.net.MalformedURLException e) {
            return frontendBaseUrl + "/usps-test";
        }
    }

    private String buildOAuthErrorRedirect(String returnUrl, Exception e) {
        String base = resolveSuccessRedirect(returnUrl);
        String encodedMessage = java.net.URLEncoder.encode(
                e.getMessage() != null ? e.getMessage() : "OAuth failed",
                java.nio.charset.StandardCharsets.UTF_8);
        String separator = base.contains("?") ? "&" : "?";
        return base + separator + OAUTH_ERROR_PARAM + "=" + encodedMessage;
    }
}
