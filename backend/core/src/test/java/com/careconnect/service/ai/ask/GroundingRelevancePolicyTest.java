package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class GroundingRelevancePolicyTest {

    @Test
    void specificMedicationDoesNotAcceptDifferentMedicationFromStrongHit() {
        final String evidence = "Insulin was increased to ten units nightly.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "Was metformin changed?", evidence, evidence, strongChunk(evidence)))
                .isFalse();
    }

    @Test
    void specificMedicationRequiresEntityInEvidenceNotElsewhereInExcerpt() {
        final String evidence = "Insulin was increased to ten units nightly.";
        final String excerpt = "Metformin was reviewed. " + evidence;

        assertThat(GroundingRelevancePolicy.isRelevant(
                "Was metformin changed?", evidence, excerpt, strongChunk(excerpt)))
                .isFalse();
    }

    @Test
    void genericMedicationQuestionAcceptsMedicationConceptEvidence() {
        final String evidence = "Insulin was increased to ten units nightly.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What medications changed?", evidence, evidence, strongChunk(evidence)))
                .isTrue();
    }

    @Test
    void genuinelyGenericQuestionMayUseStrongWholeRecordFallback() {
        final String evidence = "The patient attended a routine follow-up visit.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What happened recently?", evidence, evidence, strongChunk(evidence)))
                .isTrue();
    }

    @Test
    void nonGenericEntityCannotUseRankOnlyFallback() {
        final String evidence = "The patient attended a routine follow-up visit.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What happened with metformin?", evidence, evidence, strongChunk(evidence)))
                .isFalse();
    }

    private static RankedChunk strongChunk(final String text) {
        return new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.CALL_SUMMARY,
                "99",
                text,
                null,
                "auto",
                0.03d,
                1,
                1,
                "C1");
    }
}
