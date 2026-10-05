package com.careconnect.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * PKCE (RFC 7636) helper for the Epic SMART-on-FHIR authorization-code flow.
 *
 * <p>Net-new: there is no existing PKCE code in the repo. The {@code code_verifier} is a
 * high-entropy random string kept server-side (never sent to Epic in the authorize step);
 * the {@code code_challenge} = BASE64URL(SHA-256(verifier)) travels in the authorize URL.
 * At token exchange the verifier is presented to prove the client that started the flow is
 * the one redeeming the code.
 */
public final class PkceUtil {

    private static final SecureRandom RNG = new SecureRandom();

    private PkceUtil() {}

    /** 32 random bytes → 43-char base64url (no padding) verifier. */
    public static String newCodeVerifier() {
        byte[] b = new byte[32];
        RNG.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    /** S256 challenge: BASE64URL(SHA-256(verifier)). */
    public static String s256Challenge(String verifier) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(verifier.getBytes(StandardCharsets.US_ASCII));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable for PKCE challenge", e);
        }
    }
}
