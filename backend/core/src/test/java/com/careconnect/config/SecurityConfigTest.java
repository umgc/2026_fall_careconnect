package com.careconnect.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import org.springframework.security.crypto.password.PasswordEncoder;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link SecurityConfig}.
 * <p>
 * SecurityConfig is a Spring {@code @Configuration} class whose primary responsibility
 * tested here is producing a {@code PasswordEncoder} bean backed by BCrypt. BCrypt is
 * the industry-standard adaptive hashing algorithm for passwords: it incorporates a
 * random salt per hash, making rainbow-table and precomputed-hash attacks infeasible.
 * <p>
 * No Spring context is needed — the config class is instantiated directly, and the
 * real BCrypt implementation is exercised (not mocked) to verify both correctness and
 * security properties of the encoder.
 */
class SecurityConfigTest {

    private SecurityConfig securityConfig;

    @BeforeEach
    void setUp() throws Exception {
        securityConfig = new SecurityConfig();
    }

    @Test
    void passwordEncoder_IsCreated() throws Exception {
        // Sanity check that passwordEncoder() returns a non-null bean.
        assertNotNull(securityConfig.passwordEncoder());
    }

    @Test
    void passwordEncoder_ReturnsBCrypt() throws Exception {
        // Verifies that the returned encoder is specifically a BCryptPasswordEncoder,
        // confirming the algorithm choice rather than accepting any PasswordEncoder
        // implementation (e.g. NoOpPasswordEncoder used only for legacy/dev scenarios).
        final PasswordEncoder encoder = securityConfig.passwordEncoder();
        assertInstanceOf(
                org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder.class,
                encoder
        );
    }

    @Test
    void passwordEncoder_CanEncodeAndMatch() throws Exception {
        // Verifies the core encode/match round-trip: a raw password is hashed, the hash
        // differs from the plaintext (i.e. it is actually encoded), and matches() confirms
        // the original password against the stored hash — the critical login-time check.
        final PasswordEncoder encoder = securityConfig.passwordEncoder();
        final String raw = "testPassword123";
        final String encoded = encoder.encode(raw);

        assertNotEquals(raw, encoded);
        assertTrue(encoder.matches(raw, encoded));
    }

    @Test
    void passwordEncoder_RejectsMismatch() throws Exception {
        // Verifies that matches() returns false for a wrong password, ensuring that
        // incorrect credentials are rejected during authentication.
        final PasswordEncoder encoder = securityConfig.passwordEncoder();
        final String encoded = encoder.encode("correctPassword");

        assertFalse(encoder.matches("wrongPassword", encoded));
    }

    @Test
    void passwordEncoder_ProducesDifferentHashesForSameInput() throws Exception {
        // Verifies BCrypt's random-salt property: two calls to encode() with the same
        // plaintext produce different hashes, yet both hashes still match the original.
        // This prevents attackers from deducing which users share the same password.

        // BCrypt uses random salt, so hashes should differ
        final PasswordEncoder encoder = securityConfig.passwordEncoder();
        final String raw = "samePassword";
        final String hash1 = encoder.encode(raw);
        final String hash2 = encoder.encode(raw);

        assertNotEquals(hash1, hash2);
        // But both should still match the original
        assertTrue(encoder.matches(raw, hash1));
        assertTrue(encoder.matches(raw, hash2));
    }
}
