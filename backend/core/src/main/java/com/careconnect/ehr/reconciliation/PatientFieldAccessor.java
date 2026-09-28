package com.careconnect.ehr.reconciliation;

import java.time.Instant;
import java.util.Optional;

/**
 * Persistence contract for reading and writing {@code patient} itself. This is the ONLY path by
 * which this library ever touches {@code patient} — no adapter should hold its own direct write path
 * to {@code patient} for a field this library manages (that's the write-contract the original
 * reconciliation design established: "No adapter ever writes to patient directly").
 */
public interface PatientFieldAccessor {

    /**
     * The field's current value on {@code patient}, or empty if null/blank. An empty result is what
     * triggers the "fill when empty" rule (apply directly, no provenance comparison needed) —
     * see {@link RecencyWinsIdentityReconciler}.
     */
    Optional<String> getCurrentValue(Object patientId, String fieldName);

    /**
     * {@code patient.updated_at} for the whole row. Used only as the fallback freshness baseline for
     * a field that has never gone through this library before (Assumption A1 — see README.md). Once
     * {@link IdentityFieldProvenanceStore} has a row for a field, this is never consulted again for
     * that field.
     */
    Instant getPatientUpdatedAt(Object patientId);

    /** Writes the new value. Must be called on the same connection/transaction as the provenance lock. */
    void applyValue(Object patientId, String fieldName, String newValue);
}
