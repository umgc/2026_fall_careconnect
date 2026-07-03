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
        try {
            OAuthStateSigner.ParsedOAuthState stateData = oauthStateSigner.parse(state);
            String userId = stateData.userId();
            String returnUrl = stateData.returnUrl();

            googleOAuthService.exchange(userId, code);

            String frontendUrl;
            if (returnUrl != null && !returnUrl.isEmpty()) {
                frontendUrl = returnUrl;
            } else {
                frontendUrl = frontendBaseUrl + "/usps-test";
            }

            try {
                new java.net.URL(frontendUrl);
            } catch (java.net.MalformedURLException e) {
                frontendUrl = frontendBaseUrl + "/usps-test";
            }

            return ResponseEntity.status(302).location(URI.create(frontendUrl)).build();
        } catch (Exception e) {
            String errorUrl = frontendBaseUrl + "/usps-test?oauthError="
                    + java.net.URLEncoder.encode(e.getMessage(), java.nio.charset.StandardCharsets.UTF_8);
            return ResponseEntity.status(302).location(URI.create(errorUrl)).build();
        }
    }
}
