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
    private static final long START_TOKEN_TTL_SECONDS = 120;
    private static final String HMAC_ALGO = "HmacSHA256";
    private static final String START_TOKEN_PREFIX = "start";

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
        return buildSignedToken(userId, returnUrl, STATE_TTL_SECONDS, null);
    }

    /**
     * Short-lived token for {@code /oauth/google/start}; obtained via authenticated API.
     */
    public String signStartToken(String userId, String returnUrl) {
        return buildSignedToken(userId, returnUrl, START_TOKEN_TTL_SECONDS, START_TOKEN_PREFIX);
    }

    public ParsedOAuthState verifyStartToken(String startToken) {
        ParsedOAuthState parsed = verifySignedToken(startToken, START_TOKEN_PREFIX);
        if (parsed == null) {
            throw new IllegalArgumentException("Invalid start token");
        }
        return parsed;
    }

    public ParsedOAuthState verify(String state) {
        ParsedOAuthState parsed = verifySignedToken(state, null);
        if (parsed == null) {
            throw new IllegalArgumentException("Invalid state");
        }
        return parsed;
    }

    private String buildSignedToken(String userId, String returnUrl, long ttlSeconds, String prefix) {
        long expiresAtEpoch = Instant.now().getEpochSecond() + ttlSeconds;
        byte[] nonceBytes = new byte[16];
        secureRandom.nextBytes(nonceBytes);
        String nonce = Base64.getUrlEncoder().withoutPadding().encodeToString(nonceBytes);
        String payload = buildPayload(userId, returnUrl, expiresAtEpoch, nonce, prefix);
        String signature = hmacSign(payload);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(payload.getBytes(StandardCharsets.UTF_8))
                + "." + signature;
    }

    private ParsedOAuthState verifySignedToken(String token, String requiredPrefix) {
        if (token == null || token.isBlank()) {
            throw new IllegalArgumentException("Invalid token: missing");
        }
        int dot = token.lastIndexOf('.');
        if (dot <= 0 || dot == token.length() - 1) {
            throw new IllegalArgumentException("Invalid token: malformed");
        }
        String encodedPayload = token.substring(0, dot);
        String signature = token.substring(dot + 1);
        String payload = new String(Base64.getUrlDecoder().decode(encodedPayload), StandardCharsets.UTF_8);
        if (!constantTimeEquals(hmacSign(payload), signature)) {
            throw new IllegalArgumentException("Invalid token: signature mismatch");
        }
        String[] parts = payload.split("\\|", -1);
        if (parts.length == 5 && START_TOKEN_PREFIX.equals(parts[0])) {
            if (requiredPrefix == null) {
                throw new IllegalArgumentException("Invalid token: payload format");
            }
            if (!START_TOKEN_PREFIX.equals(requiredPrefix)) {
                return null;
            }
            return parsePayloadParts(parts[1], parts[2], parts[3]);
        }
        if (parts.length == 4 && requiredPrefix == null) {
            return parsePayloadParts(parts[0], parts[1], parts[2]);
        }
        throw new IllegalArgumentException("Invalid token: payload format");
    }

    private ParsedOAuthState parsePayloadParts(String userId, String returnUrlPart, String expiresPart) {
        long expiresAtEpoch = Long.parseLong(expiresPart);
        if (Instant.now().getEpochSecond() > expiresAtEpoch) {
            throw new IllegalArgumentException("Invalid token: expired");
        }
        String returnUrl = returnUrlPart.isBlank() ? null : returnUrlPart;
        return new ParsedOAuthState(userId, returnUrl);
    }

    private static String buildPayload(
            String userId,
            String returnUrl,
            long expiresAtEpoch,
            String nonce,
            String prefix) {
        String safeUserId = nullToEmpty(userId);
        String safeReturnUrl = nullToEmpty(returnUrl);
        if (prefix == null || prefix.isBlank()) {
            return safeUserId + "|" + safeReturnUrl + "|" + expiresAtEpoch + "|" + nonce;
        }
        return prefix + "|" + safeUserId + "|" + safeReturnUrl + "|" + expiresAtEpoch + "|" + nonce;
    }

    private String hmacSign(String payload) {
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
