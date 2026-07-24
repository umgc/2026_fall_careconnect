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
}
