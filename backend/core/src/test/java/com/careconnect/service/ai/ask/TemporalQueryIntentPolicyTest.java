package com.careconnect.service.ai.ask;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TemporalQueryIntentPolicyTest {

    @Test
    void detectsCurrentLatestAndRecentMarkers() {
        assertThat(TemporalQueryIntentPolicy.requiresDatedEvidence("What is my current BP?"))
                .isTrue();
        assertThat(TemporalQueryIntentPolicy.requiresDatedEvidence("What is the latest INR?"))
                .isTrue();
        assertThat(TemporalQueryIntentPolicy.requiresDatedEvidence("Any recent medication changes?"))
                .isTrue();
    }

    @Test
    void ignoresNonTemporalQuestions() {
        assertThat(TemporalQueryIntentPolicy.requiresDatedEvidence("Was metformin changed in March?"))
                .isFalse();
        assertThat(TemporalQueryIntentPolicy.requiresDatedEvidence("List allergies"))
                .isFalse();
    }
}
