package com.careconnect.service.ai.retrieval;

/**
 * Task 5.2 — planned retrieval narrowing for hybrid search.
 *
 * @param intent             classified query intent
 * @param medicationNameHint optional normalized medication name extracted from the query
 */
public record RetrievalPlan(QueryIntent intent, String medicationNameHint) {

    public static RetrievalPlan general() {
        return new RetrievalPlan(QueryIntent.GENERAL, null);
    }

    public boolean isMedicationTimeline() {
        return intent == QueryIntent.MEDICATION_TIMELINE;
    }
}
