package com.careconnect.service.ai.ask;

import java.text.BreakIterator;
import java.text.Normalizer;
import java.util.Locale;

/** Central Unicode policy for text crossing the Ask AI trust boundary. */
final class AskAiTextPolicy {

    private AskAiTextPolicy() {
    }

    static String normalize(final String value) {
        if (value == null) {
            return "";
        }
        final String normalized = Normalizer.normalize(value, Normalizer.Form.NFC);
        final StringBuilder safe = new StringBuilder(normalized.length());
        normalized.codePoints().forEach(codePoint -> {
            if (isBidiControl(codePoint)) {
                return;
            }
            if (Character.isISOControl(codePoint)
                    && codePoint != '\n'
                    && codePoint != '\r'
                    && codePoint != '\t') {
                safe.append(' ');
            } else {
                safe.appendCodePoint(codePoint);
            }
        });
        return safe.toString();
    }

    static String truncateGraphemes(final String value, final int maxGraphemes) {
        final String safe = normalize(value);
        if (safe.isEmpty() || maxGraphemes <= 0) {
            return "";
        }
        final BreakIterator iterator = BreakIterator.getCharacterInstance(Locale.ROOT);
        iterator.setText(safe);
        int end = iterator.first();
        for (int count = 0; count < maxGraphemes; count++) {
            final int next = iterator.next();
            if (next == BreakIterator.DONE) {
                return safe;
            }
            end = next;
        }
        return safe.substring(0, end);
    }

    static boolean containsBidiControl(final String value) {
        return value != null && value.codePoints().anyMatch(AskAiTextPolicy::isBidiControl);
    }

    private static boolean isBidiControl(final int codePoint) {
        return codePoint == 0x061C
                || codePoint == 0x200E
                || codePoint == 0x200F
                || (codePoint >= 0x202A && codePoint <= 0x202E)
                || (codePoint >= 0x2066 && codePoint <= 0x2069);
    }
}
