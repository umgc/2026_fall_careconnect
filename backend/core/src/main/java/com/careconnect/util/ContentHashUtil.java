package com.careconnect.util;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/** Shared, versioned content-hash contract for indexing event publishers and consumers. */
public final class ContentHashUtil {

    private static final String SHA_256_PREFIX = "sha256:";

    private ContentHashUtil() {
    }

    public static String sha256(final String value) {
        if (value == null) {
            return null;
        }
        try {
            final MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return SHA_256_PREFIX + HexFormat.of().formatHex(
                    digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (final NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 is unavailable", ex);
        }
    }
}
