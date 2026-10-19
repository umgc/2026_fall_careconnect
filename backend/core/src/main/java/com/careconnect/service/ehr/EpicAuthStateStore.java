package com.careconnect.service.ehr;

import org.springframework.stereotype.Component;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Issues and consumes short-lived, single-use OAuth {@code state} values for the Epic
 * authorization-code + PKCE flow, carrying the PKCE {@code code_verifier} <b>server-side</b>.
 *
 * <p>Security note: the PKCE verifier must never travel through the browser/Epic (that would
 * defeat PKCE's protection against auth-code interception), so it is kept here keyed by an
 * opaque random {@code state}. The state is single-use (removed on consume) and TTL-bound, which
 * gives the same CSRF/replay protection as a signed state for this flow. Mirrors the intent of
 * {@link com.careconnect.security.OAuthStateSigner} (HMAC + TTL + nonce) without its fixed
 * userId|returnUrl payload shape.
 *
 * <p>In-memory by design (single-node dev/sandbox). A multi-node production deployment should
 * back this with a shared short-TTL store (e.g. Redis) — noted as a hardening item.
 */
@Component
public class EpicAuthStateStore {

    private static final long TTL_SECONDS = 600;
    private static final SecureRandom RNG = new SecureRandom();

    private final Map<String, Entry> states = new ConcurrentHashMap<>();

    /** Issue a new opaque state bound to the user and PKCE verifier (no return-mode hint). */
    public String issue(Long userId, String codeVerifier) {
        return issue(userId, codeVerifier, null);
    }

    /**
     * Issue a new opaque state, additionally carrying a {@code returnMode} hint (e.g. {@code "web"})
     * so the callback can choose a web return URL vs the mobile deep link.
     */
    public String issue(Long userId, String codeVerifier, String returnMode) {
        sweepExpired();
        byte[] b = new byte[24];
        RNG.nextBytes(b);
        String state = Base64.getUrlEncoder().withoutPadding().encodeToString(b);
        states.put(state, new Entry(userId, codeVerifier, returnMode, Instant.now().plusSeconds(TTL_SECONDS)));
        return state;
    }

    /**
     * Validate and consume a state (single-use). Returns {@code null} when unknown or expired.
     */
    public Entry consume(String state) {
        if (state == null || state.isBlank()) {
            return null;
        }
        Entry entry = states.remove(state);
        if (entry == null || entry.expiresAt().isBefore(Instant.now())) {
            return null;
        }
        return entry;
    }

    private void sweepExpired() {
        Instant now = Instant.now();
        states.entrySet().removeIf(e -> e.getValue().expiresAt().isBefore(now));
    }

    /**
     * State payload held server-side for the duration of the redirect. {@code returnMode} is an
     * optional hint ({@code "web"} for the browser flow, {@code null}/other for the mobile deep link).
     */
    public record Entry(Long userId, String codeVerifier, String returnMode, Instant expiresAt) {}
}
