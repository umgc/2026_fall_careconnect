package com.careconnect.service;

import com.careconnect.model.EmailCredential;
import com.careconnect.security.TokenCryptor;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;
import org.springframework.web.util.UriUtils;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class GoogleHealthOAuthService {

    private static final EmailCredential.Provider PROVIDER = EmailCredential.Provider.GOOGLE_HEALTH;
    private static final String GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
    private static final String GOOGLE_HEALTH_EXERCISE_URL =
            "https://health.googleapis.com/v4/users/me/dataTypes/exercise/dataPoints";

    private final GoogleOAuthService googleOAuthService;
    private final TokenCryptor tokenCryptor;
    private final RestTemplate restTemplate;

    @Value("${google.oauth.client-id:${spring.security.oauth2.client.registration.google.client-id:}}")
    String clientId;

    @Value("${google.health.oauth.redirect-uri:${careconnect.baseurl:http://localhost:8080}/oauth/google-health/callback}")
    String redirectUri;

    @Value("${google.health.oauth.scope:https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly}")
    String scope;

    @Value("${google.health.oauth.frontend-url:${frontend.base-url:http://localhost:3000}/wearables}")
    String defaultFrontendReturnUrl;

    public String buildAuthorizationUrl(String userId, String returnUrl) {
        String stateData = "u:" + userId;
        if (returnUrl != null && !returnUrl.isBlank()) {
            String encodedReturnUrl = Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(returnUrl.getBytes(StandardCharsets.UTF_8));
            stateData += "|r:" + encodedReturnUrl;
        }

        return UriComponentsBuilder
                .fromHttpUrl(GOOGLE_AUTH_URL)
                .queryParam("response_type", "code")
                .queryParam("client_id", clientId)
                .queryParam("redirect_uri", UriUtils.encode(redirectUri, StandardCharsets.UTF_8))
                .queryParam("scope", UriUtils.encode(scope, StandardCharsets.UTF_8))
                .queryParam("access_type", "offline")
                .queryParam("prompt", "consent")
                .queryParam("state", UriUtils.encode(stateData, StandardCharsets.UTF_8))
                .build(true)
                .toUriString();
    }

    public OAuthCallbackResult handleCallback(String code, String state) {
        ParsedState parsedState = parseStateData(state);
        googleOAuthService.exchange(parsedState.userId(), code, PROVIDER, redirectUri);
        return new OAuthCallbackResult(parsedState.userId(), parsedState.returnUrl());
    }

    public boolean isConnected(String userId) {
        return googleOAuthService.findLatestCredential(userId, PROVIDER)
                .filter(cred -> cred.getAccessTokenEnc() != null && !cred.getAccessTokenEnc().isBlank())
                .isPresent();
    }

    public void disconnect(String userId) {
        googleOAuthService.disconnect(userId, PROVIDER);
    }

    public Map<String, Object> listExerciseDataPoints(
            String userId,
            Integer pageSize,
            String pageToken,
            String filter
    ) {
        EmailCredential credential = getFreshCredential(userId);
        String accessToken = tokenCryptor.decrypt(credential.getAccessTokenEnc());

        UriComponentsBuilder uriBuilder = UriComponentsBuilder.fromHttpUrl(GOOGLE_HEALTH_EXERCISE_URL);
        if (pageSize != null && pageSize > 0) {
            uriBuilder.queryParam("pageSize", pageSize);
        }
        if (pageToken != null && !pageToken.isBlank()) {
            uriBuilder.queryParam("pageToken", pageToken);
        }
        if (filter != null && !filter.isBlank()) {
            uriBuilder.queryParam("filter", filter);
        }

        URI uri = uriBuilder.build(true).toUri();

        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(accessToken);
        headers.setAccept(java.util.List.of(MediaType.APPLICATION_JSON));

        ResponseEntity<Map> response = restTemplate.exchange(
                uri,
                HttpMethod.GET,
                new HttpEntity<>(headers),
                Map.class
        );

        if (!response.getStatusCode().is2xxSuccessful() || response.getBody() == null) {
            throw new IllegalStateException("Google Health API call failed: " + response.getStatusCode());
        }

        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        return body;
    }

    public String defaultReturnUrl() {
        return defaultFrontendReturnUrl;
    }

    private EmailCredential getFreshCredential(String userId) {
        Optional<EmailCredential> current = googleOAuthService.findLatestCredential(userId, PROVIDER);
        if (current.isEmpty()) {
            throw new IllegalStateException("Google Health is not connected for this user");
        }
        EmailCredential refreshed = googleOAuthService.ensureFreshToken(current.get());
        if (refreshed.getAccessTokenEnc() == null || refreshed.getAccessTokenEnc().isBlank()) {
            throw new IllegalStateException("Google Health access token is unavailable");
        }
        return refreshed;
    }

    private ParsedState parseStateData(String state) {
        if (state == null || state.isBlank()) {
            throw new IllegalArgumentException("Invalid state: missing state");
        }

        String userId = null;
        String returnUrl = null;
        String[] parts = state.split("\\|");
        for (String part : parts) {
            if (part.startsWith("u:")) {
                userId = part.substring(2);
            } else if (part.startsWith("r:")) {
                String encoded = part.substring(2);
                returnUrl = new String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8);
            }
        }

        if (userId == null || userId.isBlank()) {
            throw new IllegalArgumentException("Invalid state: missing userId");
        }
        return new ParsedState(userId, returnUrl);
    }

    private record ParsedState(String userId, String returnUrl) {
    }

    public record OAuthCallbackResult(String userId, String returnUrl) {
    }
}
