package com.careconnect.service;

import com.careconnect.model.MailPiece;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Locale;

/**
 * Normalizes parsed {@link MailPiece} DTOs into canonical fields for
 * {@code usps_mailpiece} persistence (Task 3.14.5 / #122).
 */
@Component
public class MailpieceNormalizer {

    public static final String DEFAULT_CONSENT_SCOPE = "on_consent";
    private static final int MAX_IMAGE_REF_LENGTH = 1024;

    /**
     * Canonical fields produced from a parsed mailpiece + digest context.
     */
    public record NormalizedMailpiece(
            String sourceKey,
            String externalId,
            String sender,
            String summary,
            String imageRef,
            String imageFingerprint,
            String contentHash,
            OffsetDateTime receivedAt,
            LocalDate digestDate,
            String consentScope
    ) {
    }

    public NormalizedMailpiece normalize(final MailPiece piece, final OffsetDateTime digestDateTime) {
        if (piece == null) {
            throw new IllegalArgumentException("mailpiece is required");
        }
        final LocalDate digestDate = resolveDigestDate(piece, digestDateTime);
        final String externalId = firstNonBlank(trimToNull(piece.getId()), "unknown");
        final String sourceKey = buildSourceKey(digestDate, externalId);
        final String sender = sanitizeText(piece.getSender(), 512);
        final String summary = sanitizeText(piece.getSubject(), null);
        final String thumbnail = trimToNull(piece.getThumbnailUrl());
        final String imageRef = deriveImageRef(thumbnail);
        final String imageFingerprint = fingerprintImage(thumbnail);
        final String contentHash = sha256Hex(joinPipe(
                nullToEmpty(sender),
                nullToEmpty(summary),
                nullToEmpty(imageFingerprint),
                digestDate != null ? digestDate.toString() : "",
                externalId));
        final OffsetDateTime receivedAt = piece.getReceivedAt() != null
                ? piece.getReceivedAt()
                : digestDateTime;

        return new NormalizedMailpiece(
                sourceKey,
                externalId,
                sender,
                summary,
                imageRef,
                imageFingerprint,
                contentHash,
                receivedAt,
                digestDate,
                DEFAULT_CONSENT_SCOPE);
    }

    String buildSourceKey(final LocalDate digestDate, final String externalId) {
        final String datePart = digestDate != null ? digestDate.toString() : "unknown-date";
        final String idPart = externalId == null || externalId.isBlank() ? "unknown" : externalId.trim();
        final String key = datePart + "|" + idPart;
        return key.length() <= 160 ? key : key.substring(0, 160);
    }

    String deriveImageRef(final String thumbnailUrl) {
        if (thumbnailUrl == null || thumbnailUrl.isBlank()) {
            return null;
        }
        final String trimmed = thumbnailUrl.trim();
        final String lower = trimmed.toLowerCase(Locale.ROOT);
        if (lower.startsWith("data:")) {
            return null;
        }
        if (lower.startsWith("https://") || lower.startsWith("http://") || lower.startsWith("cid:")) {
            return trimmed.length() <= MAX_IMAGE_REF_LENGTH
                    ? trimmed
                    : trimmed.substring(0, MAX_IMAGE_REF_LENGTH);
        }
        return null;
    }

    String fingerprintImage(final String thumbnailUrl) {
        if (thumbnailUrl == null || thumbnailUrl.isBlank()) {
            return "";
        }
        final String trimmed = thumbnailUrl.trim();
        if (!trimmed.toLowerCase(Locale.ROOT).startsWith("data:")) {
            return sha256Hex(trimmed);
        }
        final int comma = trimmed.indexOf(',');
        if (comma <= 0 || comma >= trimmed.length() - 1) {
            return sha256Hex(trimmed);
        }
        final String base64 = trimmed.substring(comma + 1);
        try {
            final byte[] bytes = Base64.getDecoder().decode(base64);
            return sha256Hex(bytes);
        } catch (final IllegalArgumentException ex) {
            return sha256Hex(trimmed);
        }
    }

    private LocalDate resolveDigestDate(final MailPiece piece, final OffsetDateTime digestDateTime) {
        if (digestDateTime != null) {
            return digestDateTime.toLocalDate();
        }
        if (piece.getReceivedAt() != null) {
            return piece.getReceivedAt().toLocalDate();
        }
        return null;
    }

    private static String sanitizeText(final String value, final Integer maxLen) {
        final String trimmed = trimToNull(value);
        if (trimmed == null) {
            return null;
        }
        final String collapsed = trimmed.replaceAll("[\\r\\n\\t]+", " ").replaceAll(" +", " ").trim();
        if (collapsed.isEmpty()) {
            return null;
        }
        if (maxLen != null && collapsed.length() > maxLen) {
            return collapsed.substring(0, maxLen);
        }
        return collapsed;
    }

    private static String trimToNull(final String value) {
        if (value == null) {
            return null;
        }
        final String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String firstNonBlank(final String a, final String b) {
        return a != null && !a.isBlank() ? a : b;
    }

    private static String nullToEmpty(final String value) {
        return value == null ? "" : value;
    }

    private static String joinPipe(final String... parts) {
        return String.join("|", parts);
    }

    static String sha256Hex(final String value) {
        return sha256Hex(value.getBytes(StandardCharsets.UTF_8));
    }

    static String sha256Hex(final byte[] bytes) {
        try {
            final MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(bytes));
        } catch (final NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 not available", ex);
        }
    }
}
