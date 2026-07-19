package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;

import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Deterministic relevance gate for extractive Ask AI evidence.
 *
 * <p>Recognized clinical entities from {@link ClinicalEntityExtractor} must occur in
 * the evidence itself. Concept and retrieval-rank fallbacks are reserved for
 * explicitly generic clinical intent questions.
 */
final class GroundingRelevancePolicy {

    private static final Pattern WORD_BOUNDARY = Pattern.compile("[^\\p{L}\\p{N}]+");
    private static final Set<String> GRAMMAR_AND_STOP_WORDS = Set.of(
            "about", "am", "are", "be", "been", "being", "can", "compare", "could",
            "did", "do", "does", "from", "had", "has", "have", "how", "is", "may",
            "might", "must", "my", "please", "record", "records", "shall", "should",
            "show", "tell", "that", "the", "these", "this", "was", "were", "what",
            "when", "where", "which", "will", "with", "would", "your");
    private static final Set<String> GENERIC_QUERY_TERMS = Set.of(
            "allergy", "allergies", "appointment", "appointments", "care",
            "change", "changed", "changes", "current", "currently", "details", "dose",
            "dosage", "drug", "drugs", "happened", "history", "information",
            "latest", "level", "levels", "list", "medication", "medications",
            "medicine", "medicines", "meds", "most", "newest", "now", "patient",
            "pain", "recent", "recently", "status", "tablet", "tablets", "taking",
            "today", "update", "updates");
    private static final Map<String, Set<String>> CONCEPTS = Map.of(
            "medication", Set.of("medication", "medications", "medicine", "medicines",
                    "drug", "drugs", "dose", "dosage", "mg", "tablet", "metformin", "insulin"),
            "allergy", Set.of("allergy", "allergies", "allergic", "reaction"),
            "pain", Set.of("pain", "ache", "sore"),
            "appointment", Set.of("appointment", "appointments", "visit", "followup", "follow-up"));

    private GroundingRelevancePolicy() {
    }

    static boolean isRelevant(
            final String query,
            final String evidence,
            final String excerpt,
            final RankedChunk chunk) {
        final Set<String> clinicalEntities = ClinicalEntityExtractor.extract(query);
        if (!clinicalEntities.isEmpty()) {
            final Set<String> evidenceEntities = ClinicalEntityExtractor.extract(evidence);
            return clinicalEntities.stream().allMatch(entity ->
                    matchesEntity(entity, evidenceEntities));
        }

        final Set<String> queryTerms = normalizedIntentTerms(query);
        final Set<String> evidenceTerms = normalizedIntentTerms(evidence);
        if (!isGenuinelyGeneric(queryTerms)) {
            return false;
        }
        return conceptRelevant(queryTerms, evidenceTerms)
                || strongRetrievalForWholeRecord(evidence, excerpt, chunk);
    }

    private static boolean matchesEntity(
            final String queryEntity, final Set<String> evidenceEntities) {
        for (final String evidenceEntity : evidenceEntities) {
            if (sameEntityToken(queryEntity, evidenceEntity)) {
                return true;
            }
        }
        return false;
    }

    private static boolean isGenuinelyGeneric(final Set<String> queryTerms) {
        return queryTerms.isEmpty() || GENERIC_QUERY_TERMS.containsAll(queryTerms);
    }

    private static boolean sameEntityToken(final String left, final String right) {
        if (left.equals(right)) {
            return true;
        }
        // Short clinical tokens require exact equality after normalization.
        if (Math.min(left.length(), right.length()) < 4) {
            return false;
        }
        return Math.min(left.length(), right.length()) >= 5
                && (left.startsWith(right) || right.startsWith(left));
    }

    private static boolean conceptRelevant(
            final Set<String> queryTerms, final Set<String> evidenceTerms) {
        for (final Map.Entry<String, Set<String>> concept : CONCEPTS.entrySet()) {
            final boolean queryMatches = queryTerms.stream().anyMatch(term ->
                    concept.getValue().contains(term)
                            || ("meds".equals(term) && "medication".equals(concept.getKey())));
            if (queryMatches && evidenceTerms.stream().anyMatch(concept.getValue()::contains)) {
                return true;
            }
        }
        return false;
    }

    private static boolean strongRetrievalForWholeRecord(
            final String evidence,
            final String excerpt,
            final RankedChunk chunk) {
        if (chunk == null || excerpt == null || excerpt.isBlank()) {
            return false;
        }
        final boolean strongRank = (chunk.ftsRank() != null && chunk.ftsRank() <= 3)
                || (chunk.vectorRank() != null && chunk.vectorRank() <= 2);
        final boolean scoreFloor = Double.isFinite(chunk.rrfScore()) && chunk.rrfScore() >= 0.02d;
        final double coverage = (double) evidence.codePointCount(0, evidence.length())
                / Math.max(1, excerpt.codePointCount(0, excerpt.length()));
        return strongRank && scoreFloor && coverage >= 0.5d;
    }

    private static Set<String> normalizedIntentTerms(final String value) {
        final Set<String> terms = new HashSet<>();
        if (value == null) {
            return terms;
        }
        for (final String token : WORD_BOUNDARY.split(value.toLowerCase(Locale.ROOT))) {
            if (token.codePointCount(0, token.length()) >= 3
                    && !GRAMMAR_AND_STOP_WORDS.contains(token)) {
                terms.add(token);
            }
        }
        return terms;
    }
}
