package com.careconnect.service.ehr;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Short-lived, single-use state store that keeps the Cerner PKCE verifier server-side. */
@Component
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerAuthStateStore {

    private static final long TTL_SECONDS = 600;
    private static final SecureRandom RANDOM = new SecureRandom();
    private final Map<String, Entry> states = new ConcurrentHashMap<>();

    public String issue(final Long userId, final String verifier, final String returnMode) {
        states.entrySet().removeIf(entry -> entry.getValue().expiresAt().isBefore(Instant.now()));
        byte[] bytes = new byte[24];
        RANDOM.nextBytes(bytes);
        String state = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        states.put(state, new Entry(
                userId, verifier, returnMode, Instant.now().plusSeconds(TTL_SECONDS)));
        return state;
    }

    public Entry consume(final String state) {
        if (state == null || state.isBlank()) {
            return null;
        }
        Entry entry = states.remove(state);
        return entry == null || entry.expiresAt().isBefore(Instant.now()) ? null : entry;
    }

    public record Entry(Long userId, String verifier, String returnMode, Instant expiresAt) { }
}
