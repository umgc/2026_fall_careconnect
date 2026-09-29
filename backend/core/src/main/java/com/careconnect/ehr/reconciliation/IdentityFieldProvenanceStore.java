package com.careconnect.ehr.reconciliation;

import java.time.Instant;
import java.util.Optional;

/**
 * Persistence contract for {@code ehr_identity_field_provenance}. Each of the four adapter teams
 * implements this against their own persistence stack (JPA, plain JDBC, jOOQ, whatever); the library
 * only calls the interface, never a concrete framework.
 *
 * <p><b>The one rule every implementation must follow exactly:</b> {@link #lockOrCreate} MUST take a
 * row-level lock that is held until the caller's transaction commits or rolls back (in Postgres,
 * {@code SELECT ... FOR UPDATE}, or an {@code INSERT ... ON CONFLICT DO NOTHING} followed by
 * {@code SELECT ... FOR UPDATE} when the row may not exist yet). This is the entire concurrency
 * guarantee this library provides: two calls to {@link RecencyWinsIdentityReconciler#reconcile} for
 * the same {@code (patientId, fieldName)}, from any two adapters, racing at the database level, are
 * serialized by this lock, so whichever transaction commits second sees the first transaction's
 * write and compares against it correctly — a plain "read, compare in application code, then write"
 * without this lock is exactly the race this library exists to prevent (see README.md, "Why this
 * needs a lock, not just a timestamp check").
 */
public interface IdentityFieldProvenanceStore {

    /**
     * Locks and returns the current provenance row for {@code (patientId, fieldName)}, creating an
     * empty one first if none exists yet, so the lock always has a row to attach to. Must be called
     * inside the caller's transaction and must not release the lock until that transaction ends.
     */
    Optional<FieldProvenance> lockOrCreate(Object patientId, String fieldName);

    /**
     * Records {@code sourceId}/{@code sourceUpdatedAt} as the new freshest-known provenance for this
     * field. Called only after {@link #lockOrCreate} on the same connection/transaction, and only
     * when the incoming snapshot is at least as fresh as what was already there (see
     * {@link RecencyWinsIdentityReconciler} for the exact comparison and the tie-break rule).
     */
    void recordAsFreshest(Object patientId, String fieldName, Object sourceId, Instant sourceUpdatedAt);
}
