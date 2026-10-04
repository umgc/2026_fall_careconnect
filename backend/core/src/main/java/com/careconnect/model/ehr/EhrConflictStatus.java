package com.careconnect.model.ehr;

/**
 * Lifecycle of a row in {@code ehr_identity_conflict}.
 * <p>
 * There is no {@code RESOLVED} value: the reconciliation design settled on recording the
 * outcome itself, so a closed conflict is either {@code ACCEPTED} or {@code REJECTED}.
 */
public enum EhrConflictStatus {

    /**
     * Held open, awaiting the patient. Reachable <strong>only</strong> for
     * {@code field_name = 'date_of_birth'} — every other field is decided by recency in the same
     * transaction that detects the disagreement and never waits for anyone. A database CHECK
     * enforces that scoping rather than trusting application code to remember it.
     */
    PENDING,

    /** The incoming value won and was applied to {@code patient}. */
    ACCEPTED,

    /** The incoming value lost; the canonical value stands. Still recorded, so a bad
     *  crosswalk is reconstructable after the fact. */
    REJECTED
}
