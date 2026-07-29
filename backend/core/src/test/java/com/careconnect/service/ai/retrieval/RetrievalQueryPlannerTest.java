package com.careconnect.service.ai.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class RetrievalQueryPlannerTest {

    private final RetrievalQueryPlanner planner = new RetrievalQueryPlanner();

    @Test
    @DisplayName("metformin started plans medication timeline intent")
    void plan_metforminStarted_isMedicationTimeline() {
        final RetrievalPlan plan = planner.plan("When was metformin started?");

        assertThat(plan.intent()).isEqualTo(QueryIntent.MEDICATION_TIMELINE);
        assertThat(plan.isMedicationTimeline()).isTrue();
        assertThat(plan.medicationNameHint()).isEqualTo("metformin");
    }

    @Test
    @DisplayName("bare medication questions stay GENERAL with an optional med hint")
    void plan_bareMedicationQuestion_isGeneralWithHint() {
        final RetrievalPlan plan = planner.plan("What medications is the patient on?");

        assertThat(plan.intent()).isEqualTo(QueryIntent.GENERAL);
        assertThat(plan.isMedicationTimeline()).isFalse();
    }

    @Test
    @DisplayName("named medication without timeline cue stays GENERAL")
    void plan_namedMedicationWithoutTimeline_isGeneral() {
        final RetrievalPlan plan = planner.plan("Is she taking metformin?");

        assertThat(plan.intent()).isEqualTo(QueryIntent.GENERAL);
        assertThat(plan.medicationNameHint()).isEqualTo("metformin");
        assertThat(plan.isMedicationTimeline()).isFalse();
    }
}
