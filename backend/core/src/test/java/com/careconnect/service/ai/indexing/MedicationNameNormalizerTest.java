package com.careconnect.service.ai.indexing;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class MedicationNameNormalizerTest {

    @Test
    @DisplayName("Glucophage 500mg normalizes to metformin")
    void normalize_glucophageDose_isMetformin() {
        assertThat(MedicationNameNormalizer.normalize("Glucophage 500mg"))
                .isEqualTo("metformin");
    }
}
