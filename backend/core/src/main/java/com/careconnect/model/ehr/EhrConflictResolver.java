package com.careconnect.model.ehr;

/**
 * Who resolved an identity conflict.
 *
 * <p>{@link #SYSTEM} is reserved for low-risk fields the reconciler may auto-apply by
 * recency. Identity-affecting fields such as date of birth must never carry this value.
 */
public enum EhrConflictResolver {

    /** The patient chose, via the post-link confirmation flow. */
    PATIENT,

    /** A staff member chose, typically via a support path. */
    STAFF,

    /** The reconciliation service auto-applied a low-risk field by recency. */
    SYSTEM
}
