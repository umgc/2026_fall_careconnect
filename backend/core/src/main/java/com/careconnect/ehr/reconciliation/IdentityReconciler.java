package com.careconnect.ehr.reconciliation;

import java.util.List;

/**
 * The one entry point every adapter's sync job calls after upserting its own row into
 * {@code ehr_source_identity}. Implementations of this interface are the shared library; adapters
 * never re-derive the winner themselves.
 *
 * <p><b>Out of scope — do not call this for:</b>
 * <ul>
 *   <li>Medication conflicts (FR-EHR-07). That requirement says conflicting medication entries must be
 *       flagged for caregiver review, not automatically overwritten — the opposite of what this
 *       library does. Route medication reconciliation through Medication Tracker's own mechanism.</li>
 *   <li>Visit/claims cross-source reconciliation (FR-XSRC-03/04, BR-01, BR-05). That's a "flag a delta,
 *       never merge" rule over {@code ehr_visit_record}, a different problem from identity fields.</li>
 * </ul>
 * This library is scoped to {@code ehr_source_identity} vs. {@code patient} demographic fields only.
 */
public interface IdentityReconciler {

    /**
     * Reconciles every field present in {@code snapshot.fields()} against {@code patient}. Each field
     * is handled in its own provenance-locked transaction (see {@link IdentityFieldProvenanceStore}),
     * so a failure partway through leaves already-processed fields correctly committed rather than
     * rolling back the whole snapshot.
     *
     * <p>{@code date_of_birth} is the one field that can come back with
     * {@link ReconciliationOutcome.Decision#PENDING_PATIENT_CONFIRMATION} instead of a final decision
     * (2026-09-26 partial reversal — see the implementation plan's Decisions log). Every other field
     * still resolves automatically, in this same call, exactly as before.
     */
    List<ReconciliationOutcome> reconcile(SourceIdentitySnapshot snapshot);

    /**
     * The confirmation entry point the 2026-09-26 partial reversal added: finalizes the open
     * {@code PENDING date_of_birth} conflict for {@code patientId} once the patient has
     * chosen whether to accept the incoming value or keep what {@code patient.date_of_birth} already
     * holds. {@code resolved_by} is always recorded as {@code PATIENT} — there is no staff/admin
     * resolution path for this field (confirmed in the Decisions log: patient self-service only).
     *
     * <p>Call this only in response to an actual patient decision on an actual pending conflict; it is
     * not a general-purpose "resolve DOB" method for any other caller. If the candidate being
     * confirmed was superseded by a newer one in the meantime (see {@code RecencyWinsIdentityReconciler}'s
     * supersede logic), the patient is — by construction — being asked about whatever is currently
     * open, not a stale snapshot of what they were shown; a caller that needs the exact candidate the
     * patient is looking at re-read must do so immediately before presenting the confirmation UI, not
     * cache it from an earlier {@link #reconcile} call.
     *
     * @param acceptIncoming {@code true} to apply the pending candidate to {@code patient} and record
     *                       it as this field's new provenance; {@code false} to discard it and leave
     *                       {@code patient.date_of_birth} unchanged.
     * @throws IllegalStateException if no {@code date_of_birth} conflict is currently {@code PENDING}
     *                                for this patient.
     */
    ReconciliationOutcome finalizePendingDateOfBirth(Long patientId, boolean acceptIncoming);
}
