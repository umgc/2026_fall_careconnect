package com.careconnect.service.ai.ask;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ClinicalEntityExtractorTest {

    @Test
    void preservesShortClinicalTermsUnitsNumbersComparisonsAndNegation() {
        assertThat(ClinicalEntityExtractor.extract(
                "Is BP not > 140 mmHg and A1c below 7% with O2 and HR?"))
                .contains("bp", "not", ">", "140", "mmhg", "a1c", "below", "7%", "o2", "hr");
    }

    @Test
    void excludesGrammaticalAuxiliariesLikeBeen() {
        assertThat(ClinicalEntityExtractor.extract("How has my pain been recently?"))
                .doesNotContain("been", "has", "how", "my", "recently")
                .isEmpty();
    }

    @Test
    void keepsSpecificMedicationEntities() {
        assertThat(ClinicalEntityExtractor.extract("Was metformin changed?"))
                .containsExactly("metformin");
    }

    @Test
    void preservesInrAbbreviation() {
        assertThat(ClinicalEntityExtractor.extract("What is the latest INR?"))
                .containsExactly("inr");
    }

    @Test
    void takeVerbIsNotARequiredEntity() {
        assertThat(ClinicalEntityExtractor.extract("What dose of Lisinopril do I take?"))
                .containsExactly("lisinopril");
    }

    @Test
    void taskWordsAreIntentNotEntities() {
        assertThat(ClinicalEntityExtractor.extract("What tasks are due on my schedule?"))
                .isEmpty();
    }

    @Test
    void specificTaskSubjectIsStillRequired() {
        assertThat(ClinicalEntityExtractor.extract("When should I check my blood sugar?"))
                .containsExactlyInAnyOrder("check", "blood", "sugar");
    }

    @Test
    void needIsNotARequiredEntity() {
        assertThat(ClinicalEntityExtractor.extract("What does the patient need to pick up at the pharmacy?"))
                .containsExactlyInAnyOrder("pick", "pharmacy");
    }

    @Test
    void ordinalDayBecomesItsNumber() {
        assertThat(ClinicalEntityExtractor.extract("Any pending tasks on October 19th?"))
                .containsExactlyInAnyOrder("october", "19");
    }
}
