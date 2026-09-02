package com.careconnect.util;

import java.time.*;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;

public final class DateParsers {
    private static final DateTimeFormatter ISO_OFFSET = DateTimeFormatter.ISO_OFFSET_DATE_TIME;  // 2025-10-05T10:43:21.990Z
    private static final DateTimeFormatter ISO_LOCAL = DateTimeFormatter.ISO_LOCAL_DATE_TIME;   // 2025-10-05T10:43:21.990
    private static final DateTimeFormatter ISO_DATE = DateTimeFormatter.ISO_LOCAL_DATE;        // 2025-10-05
    private DateParsers() {
    }

    /**
     * Parse an ISO string with or without offset. If no offset is present, assume UTC.
     * Accepts:
     * - 2025-10-05T10:43:21.990Z
     * - 2025-10-05T10:43:21.990+05:00
     * - 2025-10-05T10:43:21.000
     * - 2025-10-05
     */
    public static OffsetDateTime parseOffsetOrLocalToUtc(String s) {
        if (s == null || s.isBlank()) {
            return OffsetDateTime.now(ZoneOffset.UTC);
        }
        final String t = s.trim();
        try {
            return OffsetDateTime.parse(t, ISO_OFFSET);
        } catch (DateTimeParseException ex1) {
            try {
                // No offset. Treat as local and pin to UTC.
                LocalDateTime ldt = LocalDateTime.parse(t, ISO_LOCAL);
                return ldt.atOffset(ZoneOffset.UTC);
            } catch (DateTimeParseException ex2) {
                // Date only. Start of day UTC.
                LocalDate ld = LocalDate.parse(t, ISO_DATE);
                return ld.atStartOfDay().atOffset(ZoneOffset.UTC);
            }
        }
    }

    /**
     * Nullable version of parseOffsetOrLocalToUtc. Returns null for null or blank input.
     */
    public static OffsetDateTime parseNullableOffsetOrLocalToUtc(String s) {
        if (s == null || s.isBlank()) return null;
        return parseOffsetOrLocalToUtc(s);
    }

    /**
     * Format as ISO_OFFSET_DATE_TIME in UTC, e.g. 2025-10-05T10:43:21.990Z.
     */
    public static String format(OffsetDateTime odt) {
        if (odt == null) return null;
        return odt.withOffsetSameInstant(ZoneOffset.UTC).format(ISO_OFFSET);
    }

    /**
     * Nullable formatter helper.
     */
    public static String formatNullable(OffsetDateTime odt) {
        return format(odt);
    }
}
