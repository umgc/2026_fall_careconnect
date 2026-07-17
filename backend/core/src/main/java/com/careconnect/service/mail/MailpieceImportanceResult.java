package com.careconnect.service.mail;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * Outcome of rule-based and/or AI-assisted mailpiece importance classification
 * (Task 3.14.6 / #123).
 */
public record MailpieceImportanceResult(
        MailpieceImportanceLevel level,
        BigDecimal confidence,
        String method,
        String engine,
        String reasoning,
        String category,
        OffsetDateTime classifiedAt
) {
    public static final String METHOD_RULES = "RULES";
    public static final String METHOD_AI = "AI";
    public static final String METHOD_HYBRID = "HYBRID";

    public static MailpieceImportanceResult of(
            final MailpieceImportanceLevel level,
            final double confidence,
            final String method,
            final String engine,
            final String reasoning,
            final String category) {
        final BigDecimal conf = BigDecimal.valueOf(clamp(confidence))
                .setScale(2, RoundingMode.HALF_UP);
        return new MailpieceImportanceResult(
                level == null ? MailpieceImportanceLevel.UNKNOWN : level,
                conf,
                method,
                engine,
                reasoning,
                category,
                OffsetDateTime.now(ZoneOffset.UTC));
    }

    private static double clamp(final double value) {
        if (Double.isNaN(value) || value < 0.0d) {
            return 0.0d;
        }
        return Math.min(1.0d, value);
    }
}
