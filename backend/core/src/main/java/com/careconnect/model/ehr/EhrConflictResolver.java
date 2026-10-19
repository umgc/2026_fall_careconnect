package com.careconnect.model.ehr;

/**
 * Who decided a conflict, mirroring {@code IdentityConflictAuditWriter.ResolvedBy} in the
 * shared reconciliation library.
 * <p>
 * There is deliberately no {@code STAFF}. Every non-DOB field resolves automatically, and the
 * 2026-09-26 DOB reversal confirmed patient self-service only — no staff or admin resolution
 * path is being built. A value that nothing can produce is worse than an absent one.
 */
public enum EhrConflictResolver {

    /** Automatic recency-wins resolution. Applies to every field except date_of_birth. */
    SYSTEM,

    /** The patient confirmed or rejected a held date_of_birth change. That field only. */
    PATIENT
}
