package com.careconnect.service.ai.ask;

import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Classifies whether an Ask AI question requires dated, newest-eligible evidence.
 *
 * <p>{@code current}, {@code latest}, and {@code recent} questions must not rely on
 * undated retrieval rank alone.
 */
final class TemporalQueryIntentPolicy {

    private static final Pattern WORD_BOUNDARY = Pattern.compile("[^\\p{L}\\p{N}]+");
    private static final Set<String> LATEST_MARKERS = Set.of(
            "current", "currently", "latest", "most", "newest", "recent", "recently",
            "now", "today");

    private TemporalQueryIntentPolicy() {
    }

    static boolean requiresDatedEvidence(final String query) {
        if (query == null || query.isBlank()) {
            return false;
        }
        for (final String token : WORD_BOUNDARY.split(query.toLowerCase(Locale.ROOT))) {
            if (!token.isEmpty() && LATEST_MARKERS.contains(token)) {
                return true;
            }
        }
        return false;
    }
}
