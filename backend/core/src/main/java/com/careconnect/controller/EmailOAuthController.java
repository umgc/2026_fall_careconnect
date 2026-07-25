package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.service.GoogleOAuthService;
import com.careconnect.service.MicrosoftOAuthService;
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
    private final MicrosoftOAuthService microsoftOAuthService;

    @Value("${google.oauth.client-id:}") String clientId;
    @Value("${google.oauth.redirect-uri:}") String redirectUri;
    @Value("${google.oauth.scope:email}") String scope;
    @Value("${google.oauth.frontend-url:http://localhost}") String frontendBaseUrl;

    @Value("${microsoft.oauth.client-id:}") String microsoftClientId;
    @Value("${microsoft.oauth.redirect-uri:}") String microsoftRedirectUri;
    @Value("${microsoft.oauth.scope:openid offline_access https://graph.microsoft.com/Mail.Read}")
    String microsoftScope;

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/google/start")
    public ResponseEntity<Void> start(@RequestParam String userId,
                                      @RequestParam(required = false) String returnUrl) {
        String stateData = "u:" + userId;
        if (returnUrl != null && !returnUrl.isEmpty()) {
            stateData += "|r:" + returnUrl;
        }

        String authUrl = UriComponentsBuilder
                .fromHttpUrl("https://accounts.google.com/o/oauth2/v2/auth")
                .queryParam("response_type", "code")
                .queryParam("client_id", clientId)
                .queryParam("redirect_uri", UriUtils.encode(redirectUri, StandardCharsets.UTF_8))
                .queryParam("scope", UriUtils.encode(scope, StandardCharsets.UTF_8))
                .queryParam("access_type", "offline")
                .queryParam("prompt", "consent")
                .queryParam("state", UriUtils.encode(stateData, StandardCharsets.UTF_8))
                .build(true)
                .toUriString();

        return ResponseEntity.status(302).location(URI.create(authUrl)).build();
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/google/callback")
    public ResponseEntity<Void> callback(@RequestParam String code, @RequestParam String state) {
        try {
            String[] stateData = parseStateData(state);
            String userId = stateData[0];
            String returnUrl = stateData[1];
            googleOAuthService.exchange(userId, code);
            String frontendUrl = (returnUrl != null && !returnUrl.isEmpty())
                    ? returnUrl
                    : frontendBaseUrl + "/usps-test";
            try {
                new java.net.URL(frontendUrl);
            } catch (java.net.MalformedURLException e) {
                frontendUrl = frontendBaseUrl + "/usps-test";
            }
            return ResponseEntity.status(302).location(URI.create(frontendUrl)).build();
        } catch (Exception e) {
            String errorUrl = "/settings?error=" + java.net.URLEncoder.encode(
                    e.getMessage(), java.nio.charset.StandardCharsets.UTF_8);
            return ResponseEntity.status(302).location(URI.create(errorUrl)).build();
        }
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/microsoft/start")
    public ResponseEntity<Void> microsoftStart(@RequestParam String userId,
                                               @RequestParam(required = false) String returnUrl) {
        String stateData = "u:" + userId;
        if (returnUrl != null && !returnUrl.isEmpty()) {
            stateData += "|r:" + returnUrl;
        }
        String authUrl = UriComponentsBuilder
                .fromHttpUrl("https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
                .queryParam("response_type", "code")
                .queryParam("client_id", microsoftClientId)
                .queryParam("redirect_uri", UriUtils.encode(microsoftRedirectUri, StandardCharsets.UTF_8))
                .queryParam("scope", UriUtils.encode(microsoftScope, StandardCharsets.UTF_8))
                .queryParam("response_mode", "query")
                .queryParam("state", UriUtils.encode(stateData, StandardCharsets.UTF_8))
                .build(true)
                .toUriString();
        return ResponseEntity.status(302).location(URI.create(authUrl)).build();
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/microsoft/callback")
    public ResponseEntity<Void> microsoftCallback(@RequestParam String code, @RequestParam String state) {
        try {
            String[] stateData = parseStateData(state);
            String userId = stateData[0];
            String returnUrl = stateData[1];
            microsoftOAuthService.exchange(userId, code);
            String frontendUrl = (returnUrl != null && !returnUrl.isEmpty())
                    ? returnUrl
                    : frontendBaseUrl + "/usps-test";
            return ResponseEntity.status(302).location(URI.create(frontendUrl)).build();
        } catch (Exception e) {
            String errorUrl = "/settings?error=" + java.net.URLEncoder.encode(
                    e.getMessage(), java.nio.charset.StandardCharsets.UTF_8);
            return ResponseEntity.status(302).location(URI.create(errorUrl)).build();
        }
    }

    private static String[] parseStateData(String state) {
        if (state == null) throw new IllegalArgumentException("Invalid state: null");
        String userId = null;
        String returnUrl = null;
        String[] parts = state.split("\\|");
        for (String part : parts) {
            if (part.startsWith("u:")) {
                userId = part.substring(2);
            } else if (part.startsWith("r:")) {
                returnUrl = part.substring(2);
            }
        }
        if (userId == null) {
            throw new IllegalArgumentException("Invalid state: missing userId");
        }
        return new String[]{userId, returnUrl};
    }
}
