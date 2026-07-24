package com.careconnect.service.ai.ask;

import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Extracts clinical specificity from Ask AI queries and evidence spans.
 *
 * <p>Short vitals abbreviations, units, numeric values, comparisons, and
 * negation are preserved. Grammatical auxiliaries such as {@code been} are
 * never treated as clinical entities.
 */
final class ClinicalEntityExtractor {

    private static final Pattern TOKEN = Pattern.compile(
            "[<>]=?|\\b\\d+(?:\\.\\d+)?%|\\b\\d+(?:\\.\\d+)?\\b|[\\p{L}\\p{N}]+",
            Pattern.UNICODE_CHARACTER_CLASS);
    private static final Set<String> SHORT_CLINICAL = Set.of(
            "bp", "hr", "inr", "a1c", "o2", "spo2", "bmi", "wbc", "rbc", "hgb", "hct",
            "egfr", "ldl", "hdl", "tsh");
    private static final Set<String> UNITS = Set.of(
            "mg", "mcg", "g", "kg", "lb", "ml", "l", "mmhg", "mmol", "bpm", "units",
            "unit", "percent", "iu");
    private static final Set<String> COMPARISONS = Set.of(
            "higher", "lower", "above", "below", "greater", "less", "increased",
            "decreased", "elevated", "high", "low", "more", "over", "under",
            "<", ">", "<=", ">=");
    private static final Set<String> NEGATIONS = Set.of(
            "not", "no", "never", "without", "deny", "denied", "denies", "negative",
            "non", "n't");
    private static final Set<String> GRAMMAR_AUXILIARIES = Set.of(
            "am", "are", "be", "been", "being", "can", "could", "did", "do", "does",
            "had", "has", "have", "is", "may", "might", "must", "shall", "should",
            "was", "were", "will", "would");
    private static final Set<String> NON_ENTITY_STOP = Set.of(
            "about", "and", "compare", "for", "from", "how", "my", "of", "or",
            "please", "show", "tell", "that", "the", "these", "this", "what",
            "when", "where", "which", "with", "your");
    /**
     * Generic clinical intent words. Kept out of specificity matching so modifiers
     * such as {@code dose} do not become mandatory evidence tokens, while short
     * vitals, units, numbers, comparisons, and negation still do.
     */
    private static final Set<String> GENERIC_CLINICAL_INTENT = Set.of(
            "allergy", "allergies", "appointment", "appointments", "care",
            "change", "changed", "changes", "current", "currently", "details",
            "dose", "dosage", "drug", "drugs", "happened", "history", "information",
            "latest", "level", "levels", "list", "medication", "medications",
            "medicine", "medicines", "meds", "most", "newest", "now", "patient",
            "pain", "recent", "recently", "record", "records", "status", "tablet",
            "tablets", "taking", "today", "update", "updates");

    private ClinicalEntityExtractor() {
    }

    static Set<String> extract(final String value) {
        final Set<String> entities = new HashSet<>();
        if (value == null || value.isBlank()) {
            return entities;
        }
        final Matcher matcher = TOKEN.matcher(value.toLowerCase(Locale.ROOT));
        while (matcher.find()) {
            final String token = normalize(matcher.group());
            if (token.isEmpty()
                    || GRAMMAR_AUXILIARIES.contains(token)
                    || NON_ENTITY_STOP.contains(token)) {
                continue;
            }
            if (isPreservedQualifier(token)) {
                entities.add(token);
                continue;
            }
            if (GENERIC_CLINICAL_INTENT.contains(token)) {
                continue;
            }
            // Longer residual clinical tokens (medications, conditions, etc.).
            if (token.codePointCount(0, token.length()) >= 4) {
                entities.add(token);
            }
        }
        return entities;
    }

    private static boolean isPreservedQualifier(final String token) {
        return SHORT_CLINICAL.contains(token)
                || UNITS.contains(token)
                || COMPARISONS.contains(token)
                || NEGATIONS.contains(token)
                || isNumeric(token);
    }

    private static boolean isNumeric(final String token) {
        if (token.isEmpty()) {
            return false;
        }
        int index = 0;
        boolean sawDigit = false;
        boolean sawDot = false;
        while (index < token.length()) {
            final int codePoint = token.codePointAt(index);
            if (Character.isDigit(codePoint)) {
                sawDigit = true;
            } else if (codePoint == '.' && !sawDot) {
                sawDot = true;
            } else if (codePoint == '%' && index == token.length() - 1 && sawDigit) {
                return true;
            } else {
                return false;
            }
            index += Character.charCount(codePoint);
        }
        return sawDigit;
    }

    private static String normalize(final String token) {
        if ("spo2".equals(token) || "o₂".equals(token)) {
            return "o2";
        }
        if ("a1c".equals(token) || "hba1c".equals(token)) {
            return "a1c";
        }
        return token;
    }
}
