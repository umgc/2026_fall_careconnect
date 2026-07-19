package com.careconnect.service.ai.indexing;

import java.util.Optional;

/** Namespaced retrieval source keys for summary tables with independent numeric IDs. */
public final class SummarySourceKey {

    public static final String CALL_KIND = "CALL_SUMMARY";
    public static final String VISIT_KIND = "VISIT_SUMMARY";

    private static final String CALL_PREFIX = "call-summary:";
    private static final String VISIT_PREFIX = "visit-summary:";

    private SummarySourceKey() {
    }

    public static String call(final long summaryId) {
        return CALL_PREFIX + summaryId;
    }

    public static String visit(final long summaryId) {
        return VISIT_PREFIX + summaryId;
    }

    public static String legacy(final long summaryId) {
        return Long.toString(summaryId);
    }

    public static Optional<Long> parseCallSummaryId(final String sourceKey) {
        if (sourceKey == null || sourceKey.isBlank()) {
            return Optional.empty();
        }
        final String numeric = sourceKey.startsWith(CALL_PREFIX)
                ? sourceKey.substring(CALL_PREFIX.length())
                : sourceKey;
        if (numeric.isBlank() || !numeric.chars().allMatch(Character::isDigit)) {
            return Optional.empty();
        }
        try {
            return Optional.of(Long.valueOf(numeric));
        } catch (final NumberFormatException ex) {
            return Optional.empty();
        }
    }
}
