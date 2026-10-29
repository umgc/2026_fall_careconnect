package com.careconnect.service.ehr;

import com.careconnect.config.CernerProperties;
import com.careconnect.dto.ehr.CernerTokenResponse;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.ehr.EhrCredentialRepository;
import com.careconnect.security.TokenCryptor;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

/** Oracle Health SMART-on-FHIR discovery, PKCE exchange, encrypted storage, and refresh. */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerOAuthService {

    private static final long EXPIRY_SKEW_SECONDS = 120;

    private final RestTemplate http;
    private final CernerProperties config;
    private final TokenCryptor tokenCryptor;
    private final EhrCredentialRepository credentials;
    private final EhrAuditService audit;

    private volatile String discoveredAuthorizationEndpoint;
    private volatile String discoveredTokenEndpoint;

    public String buildAuthorizeUrl(
            final String state, final String codeChallenge, final String launchContext) {
        UriComponentsBuilder builder = UriComponentsBuilder.fromUriString(authorizationEndpoint())
                .queryParam("response_type", "code")
                .queryParam("client_id", required(config.getClientId(), "Cerner client id"))
                .queryParam("redirect_uri", config.getRedirectUri())
                .queryParam("scope", scopesFor(launchContext))
                .queryParam("state", state)
                .queryParam("aud", fhirBaseUrl())
                .queryParam("code_challenge", codeChallenge)
                .queryParam("code_challenge_method", "S256");
        if (launchContext != null && !launchContext.isBlank()) {
            builder.queryParam("launch", launchContext);
        }
        return builder.build().encode().toUriString();
    }

    private String scopesFor(final String launchContext) {
        String scopes = config.getScopes();
        if (launchContext != null && !launchContext.isBlank()) {
            return scopes.replace("launch/patient", "launch");
        }
        return scopes;
    }

    public String buildAuthorizeUrl(final String state, final String codeChallenge) {
        return buildAuthorizeUrl(state, codeChallenge, null);
    }

    public EhrCredential exchangeAndStore(
            final Long userId, final String code, final String codeVerifier) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "authorization_code");
        form.add("code", code);
        form.add("redirect_uri", config.getRedirectUri());
        form.add("code_verifier", codeVerifier);
        addPublicClientId(form);

        CernerTokenResponse token = postForToken(form);
        if (token == null || blank(token.accessToken()) || blank(token.patient())) {
            audit.record(userId, CernerProperties.SOURCE_ORACLE_HEALTH,
                    "ORACLE_HEALTH_CONNECT", "ERROR");
            throw new CernerReauthorizationRequiredException(
                    "Oracle Health token response did not include access token and patient context");
        }

        EhrCredential credential = credentials.findFirstByUserIdAndSourceOrderByIdDesc(
                        userId, CernerProperties.SOURCE_ORACLE_HEALTH)
                .orElseGet(EhrCredential::new);
        credential.setUserId(userId);
        credential.setSource(CernerProperties.SOURCE_ORACLE_HEALTH);
        credential.setPatientFhirId(token.patient());
        credential.setFhirBaseUrl(fhirBaseUrl());
        credential.setScopes(token.scope() == null ? config.getScopes() : token.scope());
        credential.setAccessTokenEnc(tokenCryptor.encrypt(token.accessToken()));
        if (!blank(token.refreshToken())) {
            credential.setRefreshTokenEnc(tokenCryptor.encrypt(token.refreshToken()));
        }
        credential.setExpiresAt(Instant.now().plusSeconds(
                token.expiresIn() == null ? 3600 : token.expiresIn()));
        credential.setStatus(EhrCredential.Status.ACTIVE);
        credential.setLastError(null);
        EhrCredential saved = credentials.save(credential);
        audit.record(userId, CernerProperties.SOURCE_ORACLE_HEALTH,
                "ORACLE_HEALTH_CONNECT", "OK");
        return saved;
    }

    public String validAccessToken(final Long userId) {
        EhrCredential credential = requireCredential(userId);
        if (credential.getStatus() != EhrCredential.Status.ACTIVE) {
            throw new CernerReauthorizationRequiredException("Oracle Health credential needs reauthorization");
        }
        if (credential.getExpiresAt() != null
                && credential.getExpiresAt().isAfter(Instant.now().plusSeconds(EXPIRY_SKEW_SECONDS))) {
            return tokenCryptor.decrypt(credential.getAccessTokenEnc());
        }
        return refresh(credential);
    }

    /** Forces one refresh after Oracle Health rejects a token that had not yet expired locally. */
    public String refreshAccessToken(final Long userId) {
        return refresh(requireCredential(userId));
    }

    public String patientFhirId(final Long userId) {
        return requireCredential(userId).getPatientFhirId();
    }

    public Optional<EhrCredential> findCredential(final Long userId) {
        return credentials.findFirstByUserIdAndSourceOrderByIdDesc(
                userId, CernerProperties.SOURCE_ORACLE_HEALTH);
    }

    public void disconnect(final Long userId) {
        List<EhrCredential> stored = credentials.findByUserIdAndSource(
                userId, CernerProperties.SOURCE_ORACLE_HEALTH);
        if (!stored.isEmpty()) {
            credentials.deleteAll(stored);
            audit.record(userId, CernerProperties.SOURCE_ORACLE_HEALTH,
                    "ORACLE_HEALTH_DISCONNECT", "OK");
        }
    }

    private String refresh(final EhrCredential credential) {
        if (blank(credential.getRefreshTokenEnc())) {
            markNeedsReauthorization(credential, "Missing refresh token");
            throw new CernerReauthorizationRequiredException("Oracle Health refresh token is unavailable");
        }
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "refresh_token");
        form.add("refresh_token", tokenCryptor.decrypt(credential.getRefreshTokenEnc()));
        addPublicClientId(form);
        try {
            CernerTokenResponse token = postForToken(form);
            if (token == null || blank(token.accessToken())) {
                throw new CernerReauthorizationRequiredException(
                        "Oracle Health refresh returned no access token");
            }
            credential.setAccessTokenEnc(tokenCryptor.encrypt(token.accessToken()));
            if (!blank(token.refreshToken())) {
                credential.setRefreshTokenEnc(tokenCryptor.encrypt(token.refreshToken()));
            }
            credential.setExpiresAt(Instant.now().plusSeconds(
                    token.expiresIn() == null ? 3600 : token.expiresIn()));
            credential.setStatus(EhrCredential.Status.ACTIVE);
            credential.setLastError(null);
            credentials.save(credential);
            return token.accessToken();
        } catch (RuntimeException exception) {
            markNeedsReauthorization(credential, "Token refresh failed");
            if (exception instanceof CernerReauthorizationRequiredException reauthorization) {
                throw reauthorization;
            }
            throw new CernerReauthorizationRequiredException("Oracle Health token refresh failed", exception);
        }
    }

    private void addPublicClientId(final MultiValueMap<String, String> form) {
        if (!config.isConfidentialClient()) {
            form.add("client_id", required(config.getClientId(), "Cerner client id"));
        }
    }

    private CernerTokenResponse postForToken(final MultiValueMap<String, String> form) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        headers.setAccept(List.of(MediaType.APPLICATION_JSON));
        if (config.isConfidentialClient()) {
            headers.setBasicAuth(config.getClientId(), config.getClientSecret());
        }
        try {
            ResponseEntity<CernerTokenResponse> response = http.postForEntity(
                    tokenEndpoint(), new HttpEntity<>(form, headers), CernerTokenResponse.class);
            return response.getStatusCode().is2xxSuccessful() ? response.getBody() : null;
        } catch (RestClientResponseException exception) {
            // OAuth response bodies can contain operational detail; do not put them in logs/errors.
            throw exception;
        }
    }

    private EhrCredential requireCredential(final Long userId) {
        return findCredential(userId).orElseThrow(() ->
                new CernerReauthorizationRequiredException("No Oracle Health credential for user"));
    }

    private void markNeedsReauthorization(final EhrCredential credential, final String reason) {
        credential.setStatus(EhrCredential.Status.NEEDS_REAUTH);
        credential.setLastError(reason);
        credentials.save(credential);
    }

    String authorizationEndpoint() {
        discoverIfNeeded();
        return discoveredAuthorizationEndpoint;
    }

    String tokenEndpoint() {
        discoverIfNeeded();
        return discoveredTokenEndpoint;
    }

    private synchronized void discoverIfNeeded() {
        if (discoveredAuthorizationEndpoint != null && discoveredTokenEndpoint != null) {
            return;
        }
        String configuredAuthorization = config.getAuthorizationEndpoint();
        String configuredToken = config.getTokenEndpoint();
        if (!blank(configuredAuthorization) && !blank(configuredToken)) {
            discoveredAuthorizationEndpoint = secureEndpoint(configuredAuthorization);
            discoveredTokenEndpoint = secureEndpoint(configuredToken);
            return;
        }
        JsonNode discovery = http.getForObject(
                fhirBaseUrl() + "/.well-known/smart-configuration", JsonNode.class);
        if (discovery == null) {
            throw new IllegalStateException("Oracle Health SMART discovery returned no document");
        }
        discoveredAuthorizationEndpoint = secureEndpoint(
                required(discovery.path("authorization_endpoint").asText(null),
                        "SMART authorization endpoint"));
        discoveredTokenEndpoint = secureEndpoint(
                required(discovery.path("token_endpoint").asText(null), "SMART token endpoint"));
    }

    private String fhirBaseUrl() {
        String value = secureEndpoint(required(config.getFhirBaseUrl(), "Cerner FHIR base URL"));
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private static String secureEndpoint(final String value) {
        URI uri = URI.create(value);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getFragment() != null) {
            throw new IllegalStateException("Oracle Health endpoint must be an HTTPS server URL");
        }
        return uri.toString();
    }

    private static String required(final String value, final String label) {
        if (blank(value)) {
            throw new IllegalStateException(label + " is not configured");
        }
        return value;
    }

    private static boolean blank(final String value) {
        return value == null || value.isBlank();
    }

    /** Signals that the user must complete the Oracle Health authorization flow again. */
    public static class CernerReauthorizationRequiredException extends RuntimeException {
        public CernerReauthorizationRequiredException(final String message) {
            super(message);
        }

        public CernerReauthorizationRequiredException(
                final String message, final Throwable cause) {
            super(message, cause);
        }
    }
}
