package com.careconnect.service;

import static org.junit.jupiter.api.Assertions.*;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link TokenProvider}.
 *
 * <p>Validates the contract of {@code generateToken()}: every returned value
 * must be a non-null, correctly formatted UUID string, and successive calls
 * must produce distinct tokens.</p>
 */
class TokenProviderTest {

    private TokenProvider tokenProvider;

    @BeforeEach
    void setUp() throws Exception {
        tokenProvider = new TokenProvider();
    }

    // ==========================================================================
    // generateToken — format and non-null guarantees
    // ==========================================================================

    @Test
    @DisplayName("generateToken: returns a non-null value")
    void testGenerateToken_notNull() throws Exception {
        // The method must never return null, even on the first invocation.
        assertNotNull(tokenProvider.generateToken());
    }

    @Test
    @DisplayName("generateToken: returns a non-empty string")
    void testGenerateToken_notEmpty() throws Exception {
        // An empty string would be useless as a token; the result must have content.
        assertFalse(tokenProvider.generateToken().isBlank());
    }

    @Test
    @DisplayName("generateToken: token length equals the standard UUID string length (36)")
    void testGenerateToken_correctLength() throws Exception {
        // A canonical UUID string is always exactly 36 characters
        // (32 hex digits + 4 hyphens).
        assertEquals(36, tokenProvider.generateToken().length());
    }

    @Test
    @DisplayName("generateToken: token matches the standard UUID format (8-4-4-4-12)")
    void testGenerateToken_validUuidFormat() throws Exception {
        // The value must be parseable as a UUID — invalid formats would cause
        // UUID.fromString() to throw IllegalArgumentException.
        final String token = tokenProvider.generateToken();
        assertDoesNotThrow(() -> UUID.fromString(token),
                "Token '" + token + "' is not a valid UUID");
    }

    @Test
    @DisplayName("generateToken: token contains exactly four hyphens at the correct positions")
    void testGenerateToken_hyphenPositions() throws Exception {
        // UUID canonical format places hyphens at indices 8, 13, 18, and 23.
        final String token = tokenProvider.generateToken();
        assertEquals('-', token.charAt(8));
        assertEquals('-', token.charAt(13));
        assertEquals('-', token.charAt(18));
        assertEquals('-', token.charAt(23));
    }

    @Test
    @DisplayName("generateToken: token contains only hex characters and hyphens")
    void testGenerateToken_onlyHexAndHyphens() throws Exception {
        // Every character must be a lowercase hex digit or a hyphen separator.
        final String token = tokenProvider.generateToken();
        assertTrue(token.matches("[0-9a-f\\-]+"),
                "Token contains unexpected characters: " + token);
    }

    // ==========================================================================
    // generateToken — uniqueness
    // ==========================================================================

    @Test
    @DisplayName("generateToken: two successive calls return different tokens")
    void testGenerateToken_twoCallsDiffer() throws Exception {
        // Tokens are used for identity/security; the same value must not be
        // returned on back-to-back calls.
        final String first = tokenProvider.generateToken();
        final String second = tokenProvider.generateToken();
        assertNotEquals(first, second);
    }

    @Test
    @DisplayName("generateToken: 1000 successive calls all produce distinct tokens")
    void testGenerateToken_bulkUniqueness() throws Exception {
        // A large sample confirms statistical uniqueness — collisions here would
        // indicate a broken UUID source rather than an expected probability event.
        final Set<String> seen = new HashSet<>();
        for (int i = 0; i < 1000; i++) {
            final String token = tokenProvider.generateToken();
            assertTrue(seen.add(token),
                    "Duplicate token detected on iteration " + i + ": " + token);
        }
        assertEquals(1000, seen.size());
    }
}
