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
}
