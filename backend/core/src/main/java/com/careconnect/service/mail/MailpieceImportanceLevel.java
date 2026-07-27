package com.careconnect.service.mail;

import java.util.Locale;

/**
 * Importance tiers for USPS mailpieces (Task 3.14.6 / #123).
 */
public enum MailpieceImportanceLevel {
    HIGH,
    MODERATE,
    LOW,
    UNKNOWN;

    public static MailpieceImportanceLevel fromRaw(final String raw) {
        if (raw == null || raw.isBlank()) {
            return UNKNOWN;
        }
        final String value = raw.trim().toUpperCase(Locale.ROOT);
        return switch (value) {
            case "HIGH", "CRITICAL", "URGENT" -> HIGH;
            case "MODERATE", "MEDIUM", "MED" -> MODERATE;
            case "LOW", "NONE", "ROUTINE" -> LOW;
            default -> UNKNOWN;
        };
    }
}
