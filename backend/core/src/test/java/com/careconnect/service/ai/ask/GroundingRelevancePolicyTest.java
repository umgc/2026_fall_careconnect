package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class GroundingRelevancePolicyTest {

    /** A chunk with no strong rank, so only concept or entity matching can pass. */
    private static RankedChunk weakChunk(final String text) {
        return new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.TASK,
                "99",
                text,
                null,
                "auto",
                0.001d,
                null,
                null,
                "C1");
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
    void genericDoseModifierCannotSubstituteForSpecificMedicationEntity() {
        final String evidence = "The insulin dose was increased to ten units nightly.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What is the metformin dose?", evidence, evidence, strongChunk(evidence)))
                .isFalse();
    }

    @Test
    void allSpecificEntitiesMustAppearInEvidence() {
        final String evidence = "Metformin was continued without changes.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "Compare metformin and lisinopril doses", evidence, evidence, strongChunk(evidence)))
                .isFalse();
    }

    @Test
    void specificEntityWithGenericModifierIsAcceptedWhenEntityAppears() {
        final String evidence = "The metformin dosage is 500 mg twice daily.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What is the metformin dose?", evidence, evidence, strongChunk(evidence)))
                .isTrue();
    }

    @Test
    void dosageFigureIsAcceptedAsMedicationEvidenceForDrugsNotOnTheHardcodedList() {
        // Lisinopril isn't in CONCEPTS' hardcoded medication word list — an
        // exhaustive drug-name list can't be maintained, so a dosage figure like
        // "10mg" must stand on its own as evidence the span is medication-related.
        final String evidence = "Patient reports taking Lisinopril 10mg once daily each morning.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What medication is the patient taking?", evidence, evidence, strongChunk(evidence)))
                .isTrue();
    }

    @Test
    void genericDoseQuestionStillUsesMedicationConceptEvidence() {
        final String evidence = "Insulin was increased to ten units nightly.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What dose changed?", evidence, evidence, strongChunk(evidence)))
                .isTrue();
    }

    @Test
    void genericMedicationStatusQuestionRemainsGeneric() {
        final String evidence = "Insulin was increased to ten units nightly.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What is the patient's current medication status?",
                evidence,
                evidence,
                strongChunk(evidence)))
                .isTrue();
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
    void shortClinicalEntityIsRequiredInEvidence() {
        final String evidence = "Blood pressure was measured in clinic today.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What is my BP?", evidence, evidence, strongChunk(evidence)))
                .isFalse();
        assertThat(GroundingRelevancePolicy.isRelevant(
                "What is my BP?", "BP was 128/82 mmHg.", "BP was 128/82 mmHg.",
                strongChunk("BP was 128/82 mmHg.")))
                .isTrue();
    }

    @Test
    void negationIsPreservedAsRequiredEntity() {
        assertThat(GroundingRelevancePolicy.isRelevant(
                "Is the patient not allergic to penicillin?",
                "The patient is allergic to penicillin.",
                "The patient is allergic to penicillin.",
                strongChunk("The patient is allergic to penicillin.")))
                .isFalse();
        assertThat(GroundingRelevancePolicy.isRelevant(
                "Is the patient not allergic to penicillin?",
                "The patient is not allergic to penicillin.",
                "The patient is not allergic to penicillin.",
                strongChunk("The patient is not allergic to penicillin.")))
                .isTrue();
    }

    @Test
    void grammaticalBeenIsNotRequiredEvidence() {
        final String evidence = "The patient reported ongoing knee pain this week.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "How has my pain been recently?",
                evidence,
                evidence,
                strongChunk(evidence)))
                .isTrue();
    }

    @Test
    void nonGenericEntityCannotUseRankOnlyFallback() {
        final String evidence = "The patient attended a routine follow-up visit.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What happened with metformin?", evidence, evidence, strongChunk(evidence)))
                .isFalse();
    }

    @Test
    void genericTaskQuestionAcceptsTaskEvidence() {
        final String evidence = "Blood sugar check is a daily task at 07:30.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What tasks do I have?", evidence, evidence, weakChunk(evidence)))
                .isTrue();
    }

    @Test
    void genericTaskQuestionRejectsEvidenceWithoutTaskConcept() {
        final String evidence = "Metformin is taken twice daily with meals.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What tasks do I have?", evidence, evidence, weakChunk(evidence)))
                .isFalse();
    }

    @Test
    void takeVerbIsNotRequiredEvidenceForSpecificMedicationQuestion() {
        final String evidence = "Lisinopril dosage is 10mg.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "What dose of Lisinopril do I take?", evidence, evidence, weakChunk(evidence)))
                .isTrue();
    }

    @Test
    void pendingTaskQuestionAcceptsPendingTaskEvidence() {
        final String evidence = "Check Blood Sugar is pending and not yet completed.";
        final String record = "Check Blood Sugar is a HEALTH_CHECK task scheduled for 2025-10-06 at 07:30. " + evidence;

        assertThat(GroundingRelevancePolicy.isRelevant(
                "Do I have any pending tasks?", evidence, record, weakChunk(record)))
                .isTrue();
    }

    @Test
    void anyIsFillerNotARequiredTerm() {
        final String evidence = "Metformin 500mg is an active medication.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "Am I taking any medications?", evidence, evidence, weakChunk(evidence)))
                .isTrue();
    }

    @Test
    void ordinalDateQuestionMatchesWrittenDate() {
        final String evidence = "Check Blood Sugar is a HEALTH_CHECK task scheduled for Monday, October 19, 2026.";

        assertThat(GroundingRelevancePolicy.isRelevant(
                "Does the patient have any pending tasks on October 19th?", evidence, evidence, weakChunk(evidence)))
                .isTrue();
    }
}
