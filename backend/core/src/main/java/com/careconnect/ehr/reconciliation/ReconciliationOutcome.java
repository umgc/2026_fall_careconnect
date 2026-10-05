package com.careconnect.ehr.reconciliation;

/**
 * What happened for one field in one {@link IdentityReconciler#reconcile} call — or, for
 * {@code date_of_birth} only, one {@link IdentityReconciler#finalizePendingDateOfBirth} call. Returned
 * so the caller (an adapter's sync job, or whatever handles the patient's confirmation) can surface
 * the right UI for each decision: a non-blocking "your info was updated" notice for every
 * system-decided outcome (the 2026-09-26 decision replaced the confirmation modal with this for every
 * field except DOB), and a blocking confirmation prompt specifically for
 * {@link Decision#PENDING_PATIENT_CONFIRMATION} (the 2026-09-26 partial reversal restored this, for
 * {@code date_of_birth} alone) — without the library taking any opinion on how either is delivered
 * (push, in-app banner, nothing at all for a background batch job).
 */
public record ReconciliationOutcome(String fieldName, Decision decision, String appliedValue) {

    public enum Decision {
        /** patient's value was empty; the incoming value was filled in with no comparison needed. */
        FILLED_EMPTY,
        /** values already matched; nothing was written to patient (provenance may still have been refreshed). */
        ALREADY_AGREED,
        /**
         * incoming was newer (or a to-existing-favor tie); patient was updated. Never returned for
         * {@code date_of_birth} — see {@link #PENDING_PATIENT_CONFIRMATION}.
         */
        ACCEPTED_NEWER,
        /** incoming was older than the recorded/baseline provenance (or lost a tie); patient was left unchanged. */
        REJECTED_STALE,
        /**
         * {@code date_of_birth} only (2026-09-26 partial reversal): a genuine disagreement, newer than
         * what's confirmed, was detected but NOT applied. {@code appliedValue} here is the candidate
         * awaiting the patient's decision, not something already written to {@code patient} — despite
         * the field's name, nothing has been "applied" yet. Resolved later by
         * {@link IdentityReconciler#finalizePendingDateOfBirth}, or silently superseded by an even
         * newer candidate before the patient responds (see {@code RecencyWinsIdentityReconciler}).
         */
        PENDING_PATIENT_CONFIRMATION,
        /** {@code date_of_birth} only: the patient confirmed the pending candidate; patient was updated. */
        ACCEPTED_BY_PATIENT,
        /** {@code date_of_birth} only: the patient declined the pending candidate; patient was left unchanged. */
        REJECTED_BY_PATIENT
    }
}
