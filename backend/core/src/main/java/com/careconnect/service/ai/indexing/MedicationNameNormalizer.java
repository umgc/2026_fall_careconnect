package com.careconnect.service.ai.indexing;

import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Task 4.6 — lightweight medication name normalization for FR-AI-11 timeline indexing.
 *
 * <p>Strips common dose/form suffixes and applies a small alias map. Full RxNorm
 * resolution is out of scope for MVP.
 */
public final class MedicationNameNormalizer {

    private static final Pattern DOSE_OR_FORM = Pattern.compile(
            "(?i)\\b("
                    + "\\d+(\\.\\d+)?\\s*(mg|mcg|g|ml|units?|iu)\\b"
                    + "|\\b(tablet|tablets|capsule|capsules|tab|tabs|cap|caps|syrup|injection|cream|patch)\\b"
                    + "|\\bx\\s*\\d+\\b"
                    + ")");
    private static final Pattern NON_ALNUM = Pattern.compile("[^a-z0-9\\s]+");
    private static final Pattern MULTI_SPACE = Pattern.compile("\\s+");

    private static final Map<String, String> ALIASES = Map.ofEntries(
            Map.entry("glucophage", "metformin"),
            Map.entry("fortamet", "metformin"),
            Map.entry("glumetza", "metformin"),
            Map.entry("riomet", "metformin"),
            Map.entry("lipitor", "atorvastatin"),
            Map.entry("zocor", "simvastatin"),
            Map.entry("crestor", "rosuvastatin"),
            Map.entry("pravachol", "pravastatin"),
            Map.entry("norvasc", "amlodipine"),
            Map.entry("prinivil", "lisinopril"),
            Map.entry("zestril", "lisinopril"),
            Map.entry("synthroid", "levothyroxine"),
            Map.entry("levoxyl", "levothyroxine"),
            Map.entry("tylenol", "acetaminophen"),
            Map.entry("paracetamol", "acetaminophen"),
            Map.entry("advil", "ibuprofen"),
            Map.entry("motrin", "ibuprofen"),
            Map.entry("coumadin", "warfarin"),
            Map.entry("lantus", "insulin glargine"),
            Map.entry("humalog", "insulin lispro"));

    private MedicationNameNormalizer() {
    }

    public static String normalize(final String rawName) {
        if (rawName == null || rawName.isBlank()) {
            return "";
        }
        String value = rawName.toLowerCase(Locale.ROOT).trim();
        value = DOSE_OR_FORM.matcher(value).replaceAll(" ");
        value = NON_ALNUM.matcher(value).replaceAll(" ");
        value = MULTI_SPACE.matcher(value).replaceAll(" ").trim();
        if (value.isEmpty()) {
            return "";
        }
        final String alias = ALIASES.get(value);
        if (alias != null) {
            return alias;
        }
        // Alias first token when multi-word brand + strength remnants remain.
        final int space = value.indexOf(' ');
        if (space > 0) {
            final String first = value.substring(0, space);
            final String firstAlias = ALIASES.get(first);
            if (firstAlias != null) {
                return firstAlias;
            }
        }
        return value;
    }
}
