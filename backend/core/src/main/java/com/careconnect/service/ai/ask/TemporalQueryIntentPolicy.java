package com.careconnect.service.ai.ask;

import java.util.Locale;
import java.util.regex.Pattern;

/**
 * Classifies whether an Ask AI question requires dated, newest-eligible evidence.
 *
 * <p>{@code current}, {@code latest}, and {@code recent} questions must not rely on
 * undated retrieval rank alone. Bare tokens like {@code most} or {@code now} alone do not
 * trigger temporal selection — they must appear in temporal collocations.
 */
final class TemporalQueryIntentPolicy {

    private static final Pattern TEMPORAL_PHRASE = Pattern.compile(
            "\\b("
                    + "current(ly)?"
                    + "|latest"
                    + "|newest"
                    + "|recent(ly)?"
                    + "|most\\s+(recent|latest|newest)"
                    + "|right\\s+now"
                    + "|today"
                    + ")\\b",
            Pattern.CASE_INSENSITIVE);

    private TemporalQueryIntentPolicy() {
    }

    static boolean requiresDatedEvidence(final String query) {
        if (query == null || query.isBlank()) {
            return false;
        }
        return TEMPORAL_PHRASE.matcher(query.toLowerCase(Locale.ROOT)).find();
    }
}
