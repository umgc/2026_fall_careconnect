package com.careconnect.controller;

import com.careconnect.security.OAuthRedirectValidator;
import com.careconnect.security.OAuthStateSigner;
import com.careconnect.service.GoogleOAuthService;
import com.careconnect.service.MicrosoftOAuthService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.UriComponentsBuilder;
import org.springframework.web.util.UriUtils;

import java.net.URI;
import java.nio.charset.StandardCharsets;

/**
 * Browser OAuth entry points. Start endpoints are public but require a short-lived
 * HMAC {@code startToken} issued by an authenticated {@code /email-credentials/connect-url}
 * call so {@code userId} is never taken from an untrusted query param.
 */
@RestController
@RequestMapping("/oauth")
@RequiredArgsConstructor
@Slf4j
public class EmailOAuthController {

    /** Query param read by the Flutter USPS reconnect screen (also accepts legacy {@code error}). */
    static final String OAUTH_ERROR_PARAM = "oauthError";
    private static final String OAUTH_ERROR_CODE = "oauth_failed";

    private final GoogleOAuthService googleOAuthService;
    private final MicrosoftOAuthService microsoftOAuthService;
    private final OAuthStateSigner oauthStateSigner;
    private final OAuthRedirectValidator oauthRedirectValidator;

    @Value("${google.oauth.client-id:}")
    String clientId;
    @Value("${google.oauth.redirect-uri:}")
    String redirectUri;
    @Value("${google.oauth.scope:email}")
    String scope;
    @Value("${google.oauth.frontend-url:http://localhost}")
    String frontendBaseUrl;

    @Value("${microsoft.oauth.client-id:}")
    String microsoftClientId;
    @Value("${microsoft.oauth.redirect-uri:}")
    String microsoftRedirectUri;
    @Value("${microsoft.oauth.scope:openid offline_access https://graph.microsoft.com/Mail.Read}")
    String microsoftScope;

    @GetMapping("/google/start")
    public ResponseEntity<Void> start(@RequestParam String startToken) {
        return redirectToProvider(startToken, ProviderKind.GOOGLE);
    }

    @GetMapping("/google/callback")
    public ResponseEntity<Void> callback(@RequestParam String code, @RequestParam String state) {
        return handleCallback(code, state, ProviderKind.GOOGLE);
    }

    @GetMapping("/microsoft/start")
    public ResponseEntity<Void> microsoftStart(@RequestParam String startToken) {
        return redirectToProvider(startToken, ProviderKind.MICROSOFT);
    }

    @GetMapping("/microsoft/callback")
    public ResponseEntity<Void> microsoftCallback(@RequestParam String code, @RequestParam String state) {
        return handleCallback(code, state, ProviderKind.MICROSOFT);
    }

    private ResponseEntity<Void> redirectToProvider(String startToken, ProviderKind provider) {
        final OAuthStateSigner.ParsedOAuthState startData;
        try {
            startData = oauthStateSigner.verifyStartToken(startToken);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().build();
        }

        final String signedState = oauthStateSigner.sign(startData.userId(), startData.returnUrl());
        final String authUrl = switch (provider) {
            case GOOGLE -> UriComponentsBuilder
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
            case MICROSOFT -> UriComponentsBuilder
                    .fromHttpUrl("https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
                    .queryParam("response_type", "code")
                    .queryParam("client_id", microsoftClientId)
                    .queryParam("redirect_uri", UriUtils.encode(microsoftRedirectUri, StandardCharsets.UTF_8))
                    .queryParam("scope", UriUtils.encode(microsoftScope, StandardCharsets.UTF_8))
                    .queryParam("response_mode", "query")
                    .queryParam("state", UriUtils.encode(signedState, StandardCharsets.UTF_8))
                    .build(true)
                    .toUriString();
        };
        return ResponseEntity.status(302).location(URI.create(authUrl)).build();
    }

    private ResponseEntity<Void> handleCallback(String code, String state, ProviderKind provider) {
        String returnUrl = null;
        try {
            final OAuthStateSigner.ParsedOAuthState stateData = oauthStateSigner.verify(state);
            returnUrl = stateData.returnUrl();
            if (provider == ProviderKind.GOOGLE) {
                googleOAuthService.exchange(stateData.userId(), code);
            } else {
                microsoftOAuthService.exchange(stateData.userId(), code);
            }
            return ResponseEntity.status(302)
                    .location(URI.create(resolveSuccessRedirect(returnUrl)))
                    .build();
        } catch (Exception e) {
            return ResponseEntity.status(302)
                    .location(URI.create(buildOAuthErrorRedirect(returnUrl, e, provider)))
                    .build();
        }
    }

    private String resolveSuccessRedirect(String returnUrl) {
        return oauthRedirectValidator.resolveRedirect(returnUrl, frontendBaseUrl);
    }

    private String buildOAuthErrorRedirect(String returnUrl, Exception e, ProviderKind provider) {
        log.warn("{} OAuth callback failed", provider == ProviderKind.GOOGLE ? "Gmail" : "Microsoft", e);
        final String base = resolveSuccessRedirect(returnUrl);
        final String separator = base.contains("?") ? "&" : "?";
        return base + separator + OAUTH_ERROR_PARAM + "=" + OAUTH_ERROR_CODE;
    }

    private enum ProviderKind {
        GOOGLE,
        MICROSOFT
    }
}
