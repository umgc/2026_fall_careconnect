package com.careconnect.service.ai.retrieval;

import com.careconnect.service.ai.indexing.MedicationNameNormalizer;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Task 5.2 — detects medication-timeline intent so hybrid retrieval can prefilter
 * {@link RetrievalRecordType#MEDICATION_TIMELINE_EVENT} chunks (FR-AI-11).
 */
@Component
public class RetrievalQueryPlanner {

    private static final Pattern TIMELINE_CUE = Pattern.compile(
            "\\b("
                    + "start(ed|ing)?"
                    + "|stop(ped|ping)?"
                    + "|discontinu(e|ed|ing)"
                    + "|chang(e|ed|ing)"
                    + "|dose"
                    + "|dosage"
                    + "|increase(d|s)?"
                    + "|decrease(d|s)?"
                    + "|when\\s+did"
                    + "|timeline"
                    + "|initiat(e|ed|ion)"
                    + "|terminat(e|ed|ion)"
                    + ")\\b",
            Pattern.CASE_INSENSITIVE);

    private static final Pattern MEDICATION_CUE = Pattern.compile(
            "\\b("
                    + "medication|medicine|meds?|drug|rx|prescription"
                    + "|metformin|atorvastatin|simvastatin|amlodipine|lisinopril"
                    + "|levothyroxine|acetaminophen|ibuprofen|aspirin|insulin"
                    + "|glucophage|lipitor|norvasc|synthroid|tylenol|advil"
                    + ")\\b",
            Pattern.CASE_INSENSITIVE);

    private static final Pattern NAMED_MED = Pattern.compile(
            "\\b(?:on|taking|take|started|stopped|changed)\\s+([a-z][a-z0-9-]{2,})",
            Pattern.CASE_INSENSITIVE);

    private static boolean looksLikeMedicationQuestion(final String lower) {
        return lower.contains("med") || lower.contains("pill") || lower.contains("rx");
    }

    private static String extractMedicationHint(final String query) {
        final Matcher named = NAMED_MED.matcher(query);
        if (named.find()) {
            final String normalized = MedicationNameNormalizer.normalize(named.group(1));
            if (!normalized.isBlank()
                    && !normalized.equals("medication")
                    && !normalized.equals("medicine")
                    && !normalized.equals("meds")
                    && !normalized.equals("drug")) {
                return normalized;
            }
        }
        final Matcher medCue = MEDICATION_CUE.matcher(query);
        while (medCue.find()) {
            final String token = medCue.group(1);
            if (token == null) {
                continue;
            }
            final String lower = token.toLowerCase(Locale.ROOT);
            if (lower.equals("medication")
                    || lower.equals("medicine")
                    || lower.equals("med")
                    || lower.equals("meds")
                    || lower.equals("drug")
                    || lower.equals("rx")
                    || lower.equals("prescription")) {
                continue;
            }
            final String normalized = MedicationNameNormalizer.normalize(token);
            if (!normalized.isBlank()) {
                return normalized;
            }
        }
        return null;
    }

    public RetrievalPlan plan(final String query) {
        if (query == null || query.isBlank()) {
            return RetrievalPlan.general();
        }
        final String lower = query.toLowerCase(Locale.ROOT);
        final boolean medCue = MEDICATION_CUE.matcher(lower).find();
        final boolean timelineCue = TIMELINE_CUE.matcher(lower).find();
        if (!medCue && !timelineCue) {
            return RetrievalPlan.general();
        }
        // Structured medication timeline only when both medication and
        // timeline/status cues are present (or timeline cues clearly ask about meds).
        if (medCue && timelineCue) {
            return new RetrievalPlan(
                    QueryIntent.MEDICATION_TIMELINE,
                    extractMedicationHint(query));
        }
        if (timelineCue && looksLikeMedicationQuestion(lower)) {
            return new RetrievalPlan(
                    QueryIntent.MEDICATION_TIMELINE,
                    extractMedicationHint(query));
        }
        // Bare medication questions stay GENERAL (optionally with a med name hint)
        // so hybrid retrieval is not over-narrowed to timeline event chunks.
        if (medCue) {
            return new RetrievalPlan(QueryIntent.GENERAL, extractMedicationHint(query));
        }
        return RetrievalPlan.general();
    }
}
