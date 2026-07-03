package com.careconnect.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;

/**
 * Signs OAuth state parameters to prevent CSRF and tampering between start and callback.
 */
@Component
public class OAuthStateSigner {

    private static final long STATE_TTL_SECONDS = 600;
    private static final String HMAC_ALGO = "HmacSHA256";

    private final byte[] hmacKey;
    private final SecureRandom secureRandom = new SecureRandom();

    public OAuthStateSigner(@Value("${email.crypto.secret}") String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("Missing email.crypto.secret configuration");
        }
        try {
            this.hmacKey = MessageDigest.getInstance("SHA-256")
                    .digest(secret.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException("Unable to initialise OAuthStateSigner", e);
        }
    }

    public String sign(String userId, String returnUrl) {
        long expiresAtEpoch = Instant.now().getEpochSecond() + STATE_TTL_SECONDS;
        byte[] nonceBytes = new byte[16];
        secureRandom.nextBytes(nonceBytes);
        String nonce = Base64.getUrlEncoder().withoutPadding().encodeToString(nonceBytes);
        String payload = userId + "|" + nullToEmpty(returnUrl) + "|" + expiresAtEpoch + "|" + nonce;
        String signature = signPayload(payload);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(payload.getBytes(StandardCharsets.UTF_8))
                + "." + signature;
    }

    public ParsedOAuthState verify(String state) {
        if (state == null || state.isBlank()) {
            throw new IllegalArgumentException("Invalid state: missing");
        }
        int dot = state.lastIndexOf('.');
        if (dot <= 0 || dot == state.length() - 1) {
            throw new IllegalArgumentException("Invalid state: malformed");
        }
        String encodedPayload = state.substring(0, dot);
        String signature = state.substring(dot + 1);
        String payload = new String(Base64.getUrlDecoder().decode(encodedPayload), StandardCharsets.UTF_8);
        if (!constantTimeEquals(signPayload(payload), signature)) {
            throw new IllegalArgumentException("Invalid state: signature mismatch");
        }
        String[] parts = payload.split("\\|", 4);
        if (parts.length != 4) {
            throw new IllegalArgumentException("Invalid state: payload format");
        }
        long expiresAtEpoch = Long.parseLong(parts[2]);
        if (Instant.now().getEpochSecond() > expiresAtEpoch) {
            throw new IllegalArgumentException("Invalid state: expired");
        }
        String returnUrl = parts[1].isBlank() ? null : parts[1];
        return new ParsedOAuthState(parts[0], returnUrl);
    }

    /**
     * Parse legacy unsigned state for backward compatibility during rollout.
     */
    public ParsedOAuthState parseLegacy(String state) {
        if (state == null) {
            throw new IllegalArgumentException("Invalid state: null");
        }
        String userId = null;
        String returnUrl = null;
        for (String part : state.split("\\|")) {
            if (part.startsWith("u:")) {
                userId = part.substring(2);
            } else if (part.startsWith("r:")) {
                returnUrl = part.substring(2);
            }
        }
        if (userId == null || userId.isBlank()) {
            throw new IllegalArgumentException("Invalid state: missing userId");
        }
        return new ParsedOAuthState(userId, returnUrl);
    }

    public ParsedOAuthState parse(String state) {
        if (state.contains(".")) {
            return verify(state);
        }
        return parseLegacy(state);
    }

    private String signPayload(String payload) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGO);
            mac.init(new SecretKeySpec(hmacKey, HMAC_ALGO));
            byte[] digest = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to sign OAuth state", e);
        }
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    private static boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) {
            return false;
        }
        int result = 0;
        for (int i = 0; i < a.length(); i++) {
            result |= a.charAt(i) ^ b.charAt(i);
        }
        return result == 0;
    }

    public record ParsedOAuthState(String userId, String returnUrl) {}
}
