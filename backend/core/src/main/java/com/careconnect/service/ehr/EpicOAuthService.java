package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.dto.ehr.EpicTokenResponse;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.ehr.EhrCredentialRepository;
import com.careconnect.security.TokenCryptor;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * SMART-on-FHIR OAuth for Epic (Phase 0 / doc 1_8): discovery, authorize-URL build (with PKCE),
 * code→token exchange + encrypted persistence, and token refresh.
 *
 * <p>Templates: {@code GoogleHealthOAuthService.buildAuthorizationUrl} (authorize URL) and
 * {@code GoogleOAuthService.exchange/ensureFreshToken} (RestTemplate form POST + TokenCryptor +
 * refresh-on-near-expiry with re-auth on {@code invalid_grant}). No HAPI dependency.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EpicOAuthService {

    private static final long EXPIRY_SKEW_SECONDS = 120;

    private final RestTemplate http;
    private final EpicProperties cfg;
    private final TokenCryptor tokenCryptor;
    private final EhrCredentialRepository credRepo;
    private final EhrAuditService audit;

    // Cached SMART endpoints (discovered once, fallback to derived Epic defaults).
    private volatile String authorizeEndpoint;
    private volatile String tokenEndpoint;

    /** Build the Epic authorize URL. Epic REQUIRES {@code aud} = the FHIR base URL. */
    public String buildAuthorizeUrl(String state, String codeChallenge) {
        return UriComponentsBuilder.fromHttpUrl(authorizeEndpoint())
                .queryParam("response_type", "code")
                .queryParam("client_id", cfg.getClientId())
                .queryParam("redirect_uri", cfg.getRedirectUri())
                .queryParam("scope", cfg.getScopes())
                .queryParam("state", state)
                .queryParam("aud", cfg.getFhirBaseUrl())
                .queryParam("code_challenge", codeChallenge)
                .queryParam("code_challenge_method", "S256")
                // Values (notably the space-delimited SMART `scope`) are raw, not
                // pre-encoded — build unencoded then encode, so spaces become %20.
                // Using build(true) treats them as already-encoded and throws on the
                // literal spaces in the scope string.
                .build()
                .encode()
                .toUriString();
    }

    /**
     * Exchange the authorization code (with the PKCE verifier) for tokens and persist an
     * encrypted {@link EhrCredential}. Upserts the single {@code (userId, EPIC)} row.
     */
    public EhrCredential exchangeAndStore(Long userId, String code, String codeVerifier) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "authorization_code");
        form.add("code", code);
        form.add("redirect_uri", cfg.getRedirectUri());
        // client_id goes in the form body ONLY for public clients. For confidential clients it is
        // carried by the HTTP Basic auth header (postForToken); putting it in the body too makes
        // Epic treat the request as body-based client auth, find no client_secret there, and return
        // 400/401 {"error":"invalid_client"} — ignoring the Basic header.
        if (!cfg.isConfidentialClient()) {
            form.add("client_id", cfg.getClientId());
        }
        form.add("code_verifier", codeVerifier);

        EpicTokenResponse tok = postForToken(form);
        if (tok == null || tok.accessToken() == null) {
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_CONNECT", EpicProperties.SOURCE_EPIC, null, "ERROR");
            throw new IllegalStateException("Epic token exchange returned no access token");
        }

        EhrCredential cred = credRepo
                .findFirstByUserIdAndSourceOrderByIdDesc(userId, EpicProperties.SOURCE_EPIC)
                .orElseGet(EhrCredential::new);
        cred.setUserId(userId);
        cred.setSource(EpicProperties.SOURCE_EPIC);
        cred.setPatientFhirId(tok.patient());
        cred.setFhirBaseUrl(cfg.getFhirBaseUrl());
        cred.setScopes(tok.scope() != null ? tok.scope() : cfg.getScopes());
        cred.setAccessTokenEnc(tokenCryptor.encrypt(tok.accessToken()));
        if (tok.refreshToken() != null) {
            cred.setRefreshTokenEnc(tokenCryptor.encrypt(tok.refreshToken()));
        }
        cred.setExpiresAt(Instant.now().plusSeconds(tok.expiresIn() != null ? tok.expiresIn() : 3600));
        cred.setStatus(EhrCredential.Status.ACTIVE);
        cred.setLastError(null);
        EhrCredential saved = credRepo.save(cred);
        audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_CONNECT", "OK");
        return saved;
    }

    /** Return a fresh decrypted access token for the user, refreshing when near expiry. */
    public String validAccessToken(Long userId) {
        EhrCredential cred = requireCredential(userId);
        if (cred.getExpiresAt() != null
                && cred.getExpiresAt().isAfter(Instant.now().plusSeconds(EXPIRY_SKEW_SECONDS))) {
            return tokenCryptor.decrypt(cred.getAccessTokenEnc());
        }
        return refresh(cred);
    }

    public String patientFhirId(Long userId) {
        return requireCredential(userId).getPatientFhirId();
    }

    public Optional<EhrCredential> findCredential(Long userId) {
        return credRepo.findFirstByUserIdAndSourceOrderByIdDesc(userId, EpicProperties.SOURCE_EPIC);
    }

    /** Delete the stored credential(s) on disconnect. */
    public void disconnect(Long userId) {
        List<EhrCredential> all = credRepo.findByUserIdAndSource(userId, EpicProperties.SOURCE_EPIC);
        if (!all.isEmpty()) {
            credRepo.deleteAll(all);
            audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_DISCONNECT", "OK");
        }
    }

    private String refresh(EhrCredential cred) {
        String refreshEnc = cred.getRefreshTokenEnc();
        if (refreshEnc == null || refreshEnc.isBlank()) {
            markNeedsReauth(cred, "Missing refresh token");
            throw new IllegalStateException("Epic credential needs re-authorization (no refresh token)");
        }
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "refresh_token");
        form.add("refresh_token", tokenCryptor.decrypt(refreshEnc));
        // client_id in the body only for public clients; confidential clients use the Basic header.
        if (!cfg.isConfidentialClient()) {
            form.add("client_id", cfg.getClientId());
        }
        try {
            EpicTokenResponse tok = postForToken(form);
            if (tok == null || tok.accessToken() == null) {
                markNeedsReauth(cred, "Refresh returned no access token");
                throw new IllegalStateException("Epic token refresh returned no access token");
            }
            cred.setAccessTokenEnc(tokenCryptor.encrypt(tok.accessToken()));
            if (tok.refreshToken() != null) {
                cred.setRefreshTokenEnc(tokenCryptor.encrypt(tok.refreshToken()));
            }
            cred.setExpiresAt(Instant.now().plusSeconds(tok.expiresIn() != null ? tok.expiresIn() : 3600));
            cred.setStatus(EhrCredential.Status.ACTIVE);
            credRepo.save(cred);
            return tokenCryptor.decrypt(cred.getAccessTokenEnc());
        } catch (RuntimeException ex) {
            if (ex.getMessage() != null && ex.getMessage().toLowerCase().contains("invalid_grant")) {
                markNeedsReauth(cred, "invalid_grant on refresh");
            }
            throw ex;
        }
    }

    private void markNeedsReauth(EhrCredential cred, String reason) {
        cred.setStatus(EhrCredential.Status.NEEDS_REAUTH);
        cred.setLastError(reason);
        credRepo.save(cred);
    }

    private EhrCredential requireCredential(Long userId) {
        return findCredential(userId)
                .orElseThrow(() -> new IllegalStateException("No Epic credential for user " + userId));
    }

    private EpicTokenResponse postForToken(MultiValueMap<String, String> form) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        headers.setAccept(List.of(MediaType.APPLICATION_JSON));
        // Epic confidential clients authenticate at the token endpoint with HTTP Basic auth
        // (client_secret_basic): Authorization: Basic base64(client_id:client_secret). Sending the
        // secret in the form body instead returns 400 {"error":"invalid_client"}. Raw base64 (no
        // url-encoding) is used: the '/' and '=' in an Epic secret are valid literally inside the
        // credential, and Epic compares the decoded value as-is.
        if (cfg.isConfidentialClient()) {
            headers.setBasicAuth(cfg.getClientId(), cfg.getClientSecret());
        }
        try {
            ResponseEntity<EpicTokenResponse> resp = http.postForEntity(
                    tokenEndpoint(), new HttpEntity<>(form, headers), EpicTokenResponse.class);
            return resp.getStatusCode().is2xxSuccessful() ? resp.getBody() : null;
        } catch (org.springframework.web.client.RestClientResponseException ex) {
            // Surface Epic's OAuth error body (e.g. {"error":"invalid_client"}) which the default
            // RestTemplate error only logs as "400 BAD_REQUEST".
            log.warn("Epic token endpoint {} -> {} : {}",
                    tokenEndpoint(), ex.getStatusCode().value(), ex.getResponseBodyAsString());
            throw ex;
        }
    }

    // ---- SMART discovery (cached; falls back to derived Epic defaults) ----

    String authorizeEndpoint() {
        discoverIfNeeded();
        return authorizeEndpoint;
    }

    String tokenEndpoint() {
        discoverIfNeeded();
        return tokenEndpoint;
    }

    private void discoverIfNeeded() {
        if (authorizeEndpoint != null && tokenEndpoint != null) {
            return;
        }
        String base = cfg.getFhirBaseUrl();
        String oauthBase = base.contains("/api/FHIR")
                ? base.substring(0, base.indexOf("/api/FHIR"))
                : base;
        // Sensible Epic defaults; overwritten by discovery when reachable.
        String fallbackAuthorize = oauthBase + "/oauth2/authorize";
        String fallbackToken = oauthBase + "/oauth2/token";
        try {
            String discoveryUrl = base + "/.well-known/smart-configuration";
            JsonNode doc = http.getForObject(discoveryUrl, JsonNode.class);
            if (doc != null) {
                authorizeEndpoint = text(doc, "authorization_endpoint", fallbackAuthorize);
                tokenEndpoint = text(doc, "token_endpoint", fallbackToken);
                return;
            }
        } catch (RuntimeException ex) {
            log.warn("SMART discovery failed; using derived Epic OAuth endpoints ({})",
                    ex.getClass().getSimpleName());
        }
        authorizeEndpoint = fallbackAuthorize;
        tokenEndpoint = fallbackToken;
    }

    private static String text(JsonNode node, String field, String fallback) {
        JsonNode v = node.get(field);
        return v != null && v.isTextual() ? v.asText() : fallback;
    }
}
