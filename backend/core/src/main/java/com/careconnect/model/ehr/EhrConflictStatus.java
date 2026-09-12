package com.careconnect.model.ehr;

/**
 * Lifecycle of a single field-level identity conflict.
 *
 * <p>A conflict is never auto-expired into an assumed answer: it stays {@link #PENDING}
 * until a person or the reconciler explicitly resolves it.
 */
public enum EhrConflictStatus {

    /** Detected and awaiting resolution. The canonical patient value remains authoritative. */
    PENDING,

    /** The incoming source value was adopted as canonical. */
    ACCEPTED,

    /** The incoming source value was declined; the canonical patient value stands. */
    REJECTED
}
