package com.careconnect.ehr.reconciliation;

import java.time.Instant;
import java.util.Optional;

/**
 * Persistence contract for {@code ehr_identity_conflict}. Per the 2026-09-26 recency-wins decision,
 * every field except {@code date_of_birth} resolves in the same transaction it's detected in, so this
 * library never writes {@code status = 'PENDING'} for those fields — every row {@link #recordDecision}
 * writes already carries its final outcome ({@link Outcome#ACCEPTED} or {@link Outcome#REJECTED}) with
 * {@code resolved_at} set to the same instant as {@code detected_at}. {@code resolved_by} is always
 * {@link ResolvedBy#SYSTEM} for anything {@link #recordDecision} writes.
 *
 * <p><b>{@code date_of_birth} is the one named exception (2026-09-26 partial reversal — see the
 * implementation plan's Decisions log):</b> a DOB disagreement is held open as {@code PENDING} instead
 * of being decided automatically, and only ever resolves once the patient responds, via
 * {@link #resolvePendingConflict} with {@link ResolvedBy#PATIENT}. {@link #openPendingConflict} and
 * {@link #currentPendingConflict} exist only to support that one field's lifecycle — nothing else in
 * this library ever calls them. Whatever enforces {@code ehr_identity_conflict}'s CHECK constraint
 * (a {@code PENDING} row only ever for {@code field_name = 'date_of_birth'}) belongs at the schema
 * layer, not here; this interface does not defend against being called incorrectly for another field.
 *
 * <p>A row is written for every field where the incoming value differs from what's currently on
 * {@code patient} — for both outcomes, not just the accepted one. This is deliberate: it's the
 * audit trail that makes a bad auto-resolution (e.g., a non-DOB field overwritten because of a wrong
 * crosswalk) reconstructable after the fact, which is the one mitigation the accepted-risk write-up in
 * the implementation plan (§6) relies on for every field except DOB (DOB has its own, stronger
 * mitigation: nothing is overwritten until the patient agrees). Don't skip writing the REJECTED case
 * just because nothing changed on {@code patient} — "incoming was compared and lost" is exactly the
 * information a future investigation needs.
 */
public interface IdentityConflictAuditWriter {

    enum Outcome { ACCEPTED, REJECTED }

    /**
     * Who resolved a conflict. {@code STAFF} was removed in the 2026-09-26 DOB reversal: "no
     * staff/admin resolution path is being built for this (asked and confirmed — patient self-service
     * only)." {@code SYSTEM} is used for every automatic decision this library makes (which is every
     * decision, for every field, except a {@code PENDING} {@code date_of_birth} conflict);
     * {@code PATIENT} is used only by {@link #resolvePendingConflict} finalizing a
     * {@code date_of_birth} conflict.
     */
    enum ResolvedBy { SYSTEM, PATIENT }

    /**
     * Writes a final (never {@code PENDING}) decision.
     *
     * @param canonicalValueBefore {@code patient}'s value at detection time (may be null if the field
     *                             was empty — though in that case this method is not called; see
     *                             {@link RecencyWinsIdentityReconciler}, which only invokes this when
     *                             there was an actual disagreement to record).
     * @param incomingValue        the value this source offered.
     * @param sourceUpdatedAt      that value's source timestamp — the number the decision was made on.
     *                             Added 2026-09-29: this parameter did not exist, on the reasoning
     *                             that a finalized row never needs comparing against again. True, but
     *                             it conflated needing a value with storing one. {@code
     *                             ehr_identity_conflict.source_updated_at} is NOT NULL for every row,
     *                             pending or not, so no real implementation could satisfy this
     *                             interface — a gap the in-memory fake hid by storing null, which only
     *                             a database could reject. It also left the audit trail unable to do
     *                             its job: a {@code REJECTED} row recorded that a value lost without
     *                             recording the timestamp it lost with, which is the one fact needed
     *                             to tell a correct rejection from a bug.
     * @param outcome               whether the incoming value was applied to {@code patient} or discarded
     *                              as stale.
     */
    void recordDecision(
            Long patientId,
            Long sourceId,
            String fieldName,
            String canonicalValueBefore,
            String incomingValue,
            Instant sourceUpdatedAt,
            Outcome outcome,
            ResolvedBy resolvedBy,
            Instant detectedAndResolvedAt);

    /**
     * Opens a {@code PENDING} conflict — {@code date_of_birth} only. {@code resolved_at} and
     * {@code resolved_by} must stay {@code NULL} until {@link #resolvePendingConflict} is called;
     * that's the invariant {@code ck_ehr_identity_conflict_resolution} enforces at the schema layer.
     * Implementations must refuse a second call for the same {@code (patientId, fieldName)} while one
     * is already open — mirroring the real table's open-conflict uniqueness constraint — rather than
     * silently overwriting it. Callers are required to {@link #resolvePendingConflict} the existing
     * one first (see {@link RecencyWinsIdentityReconciler}'s supersede logic, which does exactly that
     * before ever calling this method a second time for the same field).
     *
     * <p>An open PENDING row's {@code sourceUpdatedAt} carries more weight than a finalized row's: it
     * is read back and compared against a possibly-newer candidate arriving before the patient
     * responds (see {@link #currentPendingConflict}), and it is what
     * {@code ehr_identity_field_provenance} records if and when the patient accepts. On a finalized
     * row the same value is history rather than a comparand — still stored, still required, but never
     * read by the algorithm.
     */
    void openPendingConflict(
            Long patientId,
            Long sourceId,
            String fieldName,
            String canonicalValueBefore,
            String incomingValue,
            Instant sourceUpdatedAt,
            Instant detectedAt);

    /**
     * The still-open {@code PENDING} conflict for {@code (patientId, fieldName)}, if any. At most one
     * can exist at a time (the real table's open-conflict uniqueness constraint; see
     * {@link #openPendingConflict}). {@code date_of_birth} only — nothing else in this library ever
     * leaves a row in this state.
     */
    Optional<PendingConflict> currentPendingConflict(Long patientId, String fieldName);

    /**
     * Whether the patient has already declined {@code incomingValue} for this field <i>from this
     * source</i>: a finalized {@code REJECTED} row with {@code resolved_by = PATIENT} and the same
     * {@code source_id}. {@code date_of_birth} only -- it lets {@link RecencyWinsIdentityReconciler}
     * discard a re-sync of a value the patient already refused instead of opening the same prompt
     * again on every sync. Scoped to the source (PR #206 review, Q3): the same value from a different,
     * independent source is corroboration and still reaches the patient.
     */
    boolean patientHasDeclined(Long patientId, Long sourceId, String fieldName, String incomingValue);

    /**
     * Finalizes the open {@code PENDING} conflict for {@code (patientId, fieldName)} — the write side
     * counterpart to {@link #currentPendingConflict}'s read, closed out with a final outcome.
     * Implementations should throw if none is open; {@link RecencyWinsIdentityReconciler} never calls
     * this without having just confirmed one exists in the same transaction.
     */
    void resolvePendingConflict(
            Long patientId,
            String fieldName,
            Outcome outcome,
            ResolvedBy resolvedBy,
            Instant resolvedAt);

    /**
     * Read-side view of an open {@code PENDING} row, as {@link #currentPendingConflict} returns it.
     *
     * @param sourceId             which {@code ehr_source} offered {@code incomingValue}.
     * @param canonicalValueBefore {@code patient}'s value at the moment this conflict was detected.
     * @param incomingValue        the value awaiting the patient's confirmation.
     * @param sourceUpdatedAt      that source's {@code source_updated_at} for this candidate — the
     *                             timestamp a later, possibly-superseding candidate is compared
     *                             against, and (if accepted) the timestamp recorded as this field's
     *                             new provenance.
     * @param detectedAt           when this conflict was opened.
     */
    record PendingConflict(
            Long sourceId,
            String canonicalValueBefore,
            String incomingValue,
            Instant sourceUpdatedAt,
            Instant detectedAt) {
    }
}
