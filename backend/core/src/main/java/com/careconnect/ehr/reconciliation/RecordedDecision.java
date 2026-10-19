package com.careconnect.ehr.reconciliation;

/**
 * A read-side view of one row written by {@link IdentityConflictAuditWriter}. Not used by
 * {@link RecencyWinsIdentityReconciler} itself — provided as a common shape for tests (including each
 * adapter team's own subclass of {@code AbstractIdentityReconciliationContractTest}) to query and
 * assert against, regardless of whether the underlying audit rows live in an in-memory fake or a real
 * {@code ehr_identity_conflict} table.
 */
public record RecordedDecision(
        String fieldName,
        String canonicalValueBefore,
        String incomingValue,
        IdentityConflictAuditWriter.Outcome outcome,
        IdentityConflictAuditWriter.ResolvedBy resolvedBy) {
}
