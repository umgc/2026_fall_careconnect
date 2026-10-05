package com.careconnect.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PkceUtilTest {

    @Test
    void newCodeVerifier_is43CharUrlSafe() {
        String v = PkceUtil.newCodeVerifier();
        assertEquals(43, v.length(), "32 random bytes → 43-char base64url");
        assertTrue(v.matches("[A-Za-z0-9_-]+"), "verifier must be URL-safe with no padding");
        assertNotEquals(PkceUtil.newCodeVerifier(), v, "verifiers must be random");
    }

    @Test
    void s256Challenge_matchesRfc7636Vector() {
        // RFC 7636 Appendix B test vector.
        String verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        String challenge = PkceUtil.s256Challenge(verifier);
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", challenge);
    }
}
