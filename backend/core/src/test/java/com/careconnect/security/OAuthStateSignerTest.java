package com.careconnect.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class OAuthStateSignerTest {

    private OAuthStateSigner signer;

    @BeforeEach
    void setUp() {
        signer = new OAuthStateSigner("unit-test-secret-32-bytes-long!!!");
    }

    @Test
    void signAndVerify_roundTrip() {
        String state = signer.sign("user-42", "http://localhost:3000/usps-test");
        OAuthStateSigner.ParsedOAuthState parsed = signer.verify(state);
        assertEquals("user-42", parsed.userId());
        assertEquals("http://localhost:3000/usps-test", parsed.returnUrl());
    }

    @Test
    void parseLegacyState_supportsUnsignedFormat() {
        OAuthStateSigner.ParsedOAuthState parsed = signer.parseLegacy("u:99|r:http://app/page");
        assertEquals("99", parsed.userId());
        assertEquals("http://app/page", parsed.returnUrl());
    }

    @Test
    void verify_rejectsTamperedSignature() {
        String state = signer.sign("user-1", null);
        String tampered = state.substring(0, state.length() - 2) + "xx";
        assertThrows(IllegalArgumentException.class, () -> signer.verify(tampered));
    }
}
