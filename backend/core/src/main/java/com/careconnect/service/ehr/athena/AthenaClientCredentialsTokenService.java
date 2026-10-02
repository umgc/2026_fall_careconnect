package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.dto.ehr.AthenaTokenResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.locks.ReentrantLock;

/**
 * 2-legged ({@code client_credentials}) token acquisition for athenahealth.
 *
 * <p>Deliberately much smaller than the Epic equivalent, because the backend leg has no
 * authorization code, no PKCE, no {@code state}, no redirect and no refresh token. The token
 * represents the APPLICATION, not a user, so there is one token per process rather than a row
 * per user: nothing is persisted and nothing is encrypted at rest.
 *
 * <p>Caching is a correctness requirement, not an optimization. athena's token endpoint has its
 * own quota well below the documented API rate limit; three rapid token requests against the
 * preview host returned {@code 429 Quota Exceeded}. So the token is cached until near expiry and
 * acquisition is single-flight: concurrent callers wait on one in-progress request instead of
 * each firing their own.
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.athena.enabled", havingValue = "true")
public class AthenaClientCredentialsTokenService implements AthenaTokenProvider {

    /** Renew this far ahead of expiry so an in-flight call cannot age out mid-request. */
    private static final long EXPIRY_SKEW_SECONDS = 120;

    /** Fallback when athena omits {@code expires_in}; the observed value is 3600. */
    private static final long DEFAULT_TTL_SECONDS = 3600;

    private final RestTemplate http;
    private final AthenaProperties cfg;

    private final ReentrantLock lock = new ReentrantLock();
    private volatile CachedToken cached;

    public AthenaClientCredentialsTokenService(final RestTemplate http, final AthenaProperties cfg) {
        this.http = http;
        this.cfg = cfg;
    }

    @Override
    public String accessToken() {
        return valid().token();
    }

    @Override
    public Set<String> grantedScopes() {
        return valid().scopes();
    }

    /** Return a cached token that is comfortably unexpired, acquiring a new one if needed. */
    private CachedToken valid() {
        final CachedToken current = cached;
        if (current != null && current.usableAt(Instant.now())) {
            return current;
        }
        lock.lock();
        try {
            // Re-check inside the lock: another thread may have refreshed while we waited, and
            // re-requesting here is exactly what trips athena's token-endpoint quota.
            final CachedToken afterWait = cached;
            if (afterWait != null && afterWait.usableAt(Instant.now())) {
                return afterWait;
            }
            return acquire();
        } finally {
            lock.unlock();
        }
    }

    /** Caller must hold {@link #lock}. */
    private CachedToken acquire() {
        if (!cfg.hasCredentials()) {
            throw new IllegalStateException(
                    "athenahealth client id/secret are not configured (athena.oauth.client-id/-secret)");
        }

        final MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "client_credentials");
        form.add("scope", cfg.getScopes());

        final HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        headers.setAccept(List.of(MediaType.APPLICATION_JSON));
        // athena also supports client_secret_post, but Basic (client_secret_basic) keeps the
        // secret out of the request body and out of anything that logs bodies.
        headers.setBasicAuth(cfg.getClientId(), cfg.getClientSecret());

        final AthenaTokenResponse body;
        try {
            final ResponseEntity<AthenaTokenResponse> resp = http.postForEntity(
                    cfg.getTokenUrl(), new HttpEntity<>(form, headers), AthenaTokenResponse.class);
            body = resp.getBody();
        } catch (RestClientResponseException ex) {
            if (ex.getStatusCode().value() == HttpStatus.TOO_MANY_REQUESTS.value()) {
                return onQuotaExceeded();
            }
            throw describe(ex);
        }

        if (body == null || body.accessToken() == null || body.accessToken().isBlank()) {
            throw new IllegalStateException("athenahealth token endpoint returned no access_token");
        }

        final long ttl = body.expiresIn() != null ? body.expiresIn() : DEFAULT_TTL_SECONDS;
        final Set<String> granted = parseScopes(body.scope());
        warnOnNarrowedScopes(granted);

        final CachedToken fresh = new CachedToken(
                body.accessToken(), granted, Instant.now().plusSeconds(ttl));
        cached = fresh;
        log.debug("Acquired athenahealth token, valid {}s, scopes={}", ttl, granted);
        return fresh;
    }

    /**
     * The token endpoint quota is tighter than the API rate limit. If the previous token has not
     * hard-expired, keep using it through the renewal skew rather than failing the caller.
     */
    private CachedToken onQuotaExceeded() {
        final CachedToken stale = cached;
        if (stale != null && !stale.expiredAt(Instant.now())) {
            log.warn("athenahealth token endpoint returned 429; reusing the existing token "
                    + "({}s until expiry)", stale.secondsUntilExpiry(Instant.now()));
            return stale;
        }
        throw new IllegalStateException(
                "athenahealth token endpoint quota exceeded (429) and no usable cached token");
    }

    /**
     * Turn athena's OAuth error bodies into something diagnosable. A plain {@code RestTemplate}
     * failure surfaces only "400 BAD_REQUEST", which hides the error that actually occurs here.
     */
    private RuntimeException describe(final RestClientResponseException ex) {
        final String responseBody = ex.getResponseBodyAsString();
        final int status = ex.getStatusCode().value();
        log.warn("athenahealth token endpoint {} -> {} : {}", cfg.getTokenUrl(), status, responseBody);

        if (responseBody != null && responseBody.contains("Invalid Scope")) {
            return new IllegalStateException(
                    "athenahealth rejected the requested scopes. Every scope in athena.oauth.scopes "
                    + "must be configured on the portal app, and wildcards are not permitted. "
                    + "Requested: " + cfg.getScopes(), ex);
        }
        return new IllegalStateException(
                "athenahealth token request failed (HTTP " + status + "): " + responseBody, ex);
    }

    private void warnOnNarrowedScopes(final Set<String> granted) {
        final Set<String> missing = new LinkedHashSet<>(cfg.requestedScopes());
        missing.removeAll(granted);
        if (!missing.isEmpty()) {
            log.warn("athenahealth granted fewer scopes than requested; missing {}. Resource types "
                    + "needing these will return 403 and must be skipped.", missing);
        }
    }

    private static Set<String> parseScopes(final String scope) {
        if (scope == null || scope.isBlank()) {
            return Set.of();
        }
        return new LinkedHashSet<>(Arrays.asList(scope.trim().split("\\s+")));
    }

    /** Immutable cached token. */
    private record CachedToken(String token, Set<String> scopes, Instant expiresAt) {

        /** Usable with room to spare, i.e. outside the renewal skew. */
        boolean usableAt(final Instant now) {
            return expiresAt.isAfter(now.plusSeconds(EXPIRY_SKEW_SECONDS));
        }

        boolean expiredAt(final Instant now) {
            return !expiresAt.isAfter(now);
        }

        long secondsUntilExpiry(final Instant now) {
            return Math.max(0, expiresAt.getEpochSecond() - now.getEpochSecond());
        }
    }
}
