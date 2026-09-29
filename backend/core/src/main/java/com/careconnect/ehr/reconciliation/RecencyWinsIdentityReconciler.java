package com.careconnect.ehr.reconciliation;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

/**
 * The shared reconciliation pattern, decided 2026-09-26 and partially reversed the same day: every
 * field on {@code ehr_source_identity} is compared against {@code patient}, and whichever side has the
 * more recent provenance timestamp wins — for every field <b>except {@code date_of_birth}</b>, which
 * instead holds a genuine disagreement open as {@code PENDING} until the patient confirms it. There
 * are no field-risk tiers beyond this one named exception, and no {@code PENDING} state for any other
 * field; every non-DOB decision is made and recorded in the same transaction it was detected in.
 *
 * <h2>The algorithm, precisely</h2>
 * For each {@code (fieldName, incomingValue)} in the snapshot, in its own transaction:
 * <ol>
 *   <li>Lock (or create) the {@code ehr_identity_field_provenance} row for
 *       {@code (patientId, fieldName)} via {@link IdentityFieldProvenanceStore#lockOrCreate}. This
 *       lock is held for the rest of this field's processing, which is what makes two concurrent
 *       adapters racing on the same field serialize correctly instead of both reading stale state —
 *       including, for {@code date_of_birth}, two concurrent disagreements racing to open or supersede
 *       the same {@code PENDING} conflict (see {@link #finalizePendingDateOfBirth}, which takes the
 *       same lock for the same reason).</li>
 *   <li>Read {@code patient}'s current value for the field.</li>
 *   <li><b>If {@code patient}'s value is empty</b>: apply the incoming value directly — no timestamp
 *       comparison, no audit row, no {@code PENDING} detour even for {@code date_of_birth} (matches
 *       the original design's "fill/update field directly" rule for an empty target: there is nothing
 *       to disagree with yet). Provenance is still recorded so future comparisons have a baseline.</li>
 *   <li><b>If the incoming value equals the current value</b>: nothing to apply, for any field,
 *       {@code date_of_birth} included. Provenance is still refreshed if this source is now the
 *       freshest known one for the field.</li>
 *   <li><b>Otherwise</b> (a real disagreement): compare {@code snapshot.sourceUpdatedAt()} against the
 *       locked provenance's timestamp — or, if no provenance row existed yet, against the snapshot's
 *       single {@code patient.updated_at} baseline (Assumption A1, see README.md; this is a product
 *       decision recorded as an assumption, not a settled requirement, and should be confirmed).
 *       <ul>
 *         <li><i>Every field except {@code date_of_birth}:</i>
 *           <ul>
 *             <li>Incoming strictly newer: apply it, write an {@code ACCEPTED} audit row,
 *                 {@code resolved_by = SYSTEM}.</li>
 *             <li>Incoming strictly older, or exactly equal (Assumption A2 — ties favor the existing
 *                 value, so repeated syncs at the same instant never flip a value back and forth):
 *                 leave {@code patient} unchanged, write a {@code REJECTED} audit row (still written —
 *                 see {@link IdentityConflictAuditWriter} for why).</li>
 *           </ul>
 *         </li>
 *         <li><i>{@code date_of_birth} only (2026-09-26 partial reversal):</i> see
 *             {@link #reconcileDateOfBirthDisagreement} — the same newer-than-baseline test decides
 *             whether the incoming value is even a candidate, but a candidate is held {@code PENDING}
 *             for the patient rather than applied. Assumption A3 (see README.md) governs what happens
 *             if a second disagreement arrives while one is already pending.</li>
 *       </ul>
 *   </li>
 *   <li>If the incoming timestamp is newer than (or equal to, to keep the provenance row itself
 *       monotonic) what was recorded, refresh {@code ehr_identity_field_provenance} to point at this
 *       source and timestamp. For {@code date_of_birth}, this step is skipped entirely while a
 *       disagreement is only {@code PENDING} — provenance must keep reflecting the last value actually
 *       on {@code patient}, not a merely-proposed one — and happens instead inside
 *       {@link #finalizePendingDateOfBirth} if and when the patient accepts.</li>
 * </ol>
 *
 * A blank/null incoming value for a field is never considered — that field is skipped entirely for
 * this snapshot, on the reasoning that "this adapter has no value for this field" should never be
 * treated as "this adapter asserts this field should be blank."
 *
 * <h2>One baseline per snapshot (fixed 2026-09-29)</h2>
 * The Assumption A1 fallback — {@code patient.updated_at}, used when a field has no provenance row —
 * is read <b>once per snapshot</b>, before any field is processed, and that one value serves every
 * field.
 *
 * <p>It has to be, because {@code updated_at} is a property of the row, not of the field, and
 * applying <i>any</i> field advances it. Reading it per field meant that within a single snapshot —
 * every field of which shares one {@code source_updated_at} — the first disagreeing field to be
 * applied raised the baseline above the snapshot's own timestamp, and every later field still
 * lacking provenance then lost to a bar the snapshot itself had just raised. Two fields that both
 * legitimately beat the baseline would see only the first one land, and on the next sync the loser
 * faced an even newer {@code updated_at}: a field could be locked out indefinitely, silently, with
 * a {@code REJECTED_STALE} audit row that looked entirely reasonable on its own.
 *
 * <p>This was unreachable before 2026-09-29 — {@code patient} carried no {@code updated_at} at all,
 * so A1 had nothing to read — and surfaced the moment the column existed. See
 * {@code JpaPatientFieldAccessorPostgresTest} TC-EHR-PACC-006, which drives this exact scenario.
 *
 * <p>Note what is <i>not</i> hoisted: a field that <b>does</b> have a provenance row still compares
 * against that row's timestamp, read fresh inside the field's own transaction while its lock is
 * held. That read must stay per field — it is how a concurrent adapter's just-committed write is
 * observed, and hoisting it would undo the concurrency guarantee the lock exists to provide.
 */
public final class RecencyWinsIdentityReconciler implements IdentityReconciler {

    /** The one field this algorithm treats differently (2026-09-26 partial reversal). */
    private static final String DATE_OF_BIRTH = "date_of_birth";

    private final IdentityFieldProvenanceStore provenanceStore;
    private final PatientFieldAccessor patientAccessor;
    private final IdentityConflictAuditWriter auditWriter;
    private final TransactionRunner transactionRunner;

    public RecencyWinsIdentityReconciler(
            IdentityFieldProvenanceStore provenanceStore,
            PatientFieldAccessor patientAccessor,
            IdentityConflictAuditWriter auditWriter,
            TransactionRunner transactionRunner) {
        this.provenanceStore = Objects.requireNonNull(provenanceStore);
        this.patientAccessor = Objects.requireNonNull(patientAccessor);
        this.auditWriter = Objects.requireNonNull(auditWriter);
        this.transactionRunner = Objects.requireNonNull(transactionRunner);
    }

    @Override
    public List<ReconciliationOutcome> reconcile(SourceIdentitySnapshot snapshot) {
        // Read the Assumption A1 fallback baseline ONCE, before any field is processed, and use that
        // one value for every field in this snapshot (fixed 2026-09-29; see the class javadoc's
        // "One baseline per snapshot" section for what reading it per field did instead).
        //
        // Eagerly, not lazily-memoized, even though a snapshot whose fields all have provenance will
        // never consult it. The fill-empty path applies a value without ever computing a baseline, so
        // a lazy read could be triggered for the first time by a *later* field, after an earlier
        // field had already advanced patient.updated_at -- reintroducing exactly the bug this fixes,
        // in a form that only shows up when the first field happens to be empty. One extra read per
        // snapshot is worth not having that edge.
        Instant fallbackBaseline = patientAccessor.getPatientUpdatedAt(snapshot.patientId());

        List<ReconciliationOutcome> outcomes = new ArrayList<>();
        for (var entry : snapshot.fields().entrySet()) {
            String fieldName = entry.getKey();
            String incomingValue = entry.getValue();
            if (incomingValue == null || incomingValue.isBlank()) {
                continue; // never treat "no value supplied" as "value should be blank"
            }
            AtomicReference<ReconciliationOutcome> outcomeRef = new AtomicReference<>();
            transactionRunner.runInTransaction(() -> outcomeRef.set(
                    reconcileOneFieldLocked(snapshot, fieldName, incomingValue, fallbackBaseline)));
            outcomes.add(outcomeRef.get());
        }
        return outcomes;
    }

    @Override
    public ReconciliationOutcome finalizePendingDateOfBirth(Object patientId, boolean acceptIncoming) {
        AtomicReference<ReconciliationOutcome> outcomeRef = new AtomicReference<>();
        transactionRunner.runInTransaction(() ->
                outcomeRef.set(finalizePendingDateOfBirthLocked(patientId, acceptIncoming)));
        return outcomeRef.get();
    }

    /**
     * Runs entirely inside the caller's transaction, with the provenance row already locked by the
     * time this returns from {@code lockOrCreate}. Package-private (not private) so a test can
     * exercise one field directly under simulated concurrency without going through the public
     * per-snapshot API.
     *
     * @param fallbackBaseline the Assumption A1 baseline, captured once for the whole snapshot by
     *                         {@link #reconcile}. Used only when this field has no provenance row;
     *                         a field that has one compares against that instead, read fresh under
     *                         the lock so a concurrent adapter's write is always seen.
     */
    ReconciliationOutcome reconcileOneFieldLocked(
            SourceIdentitySnapshot snapshot, String fieldName, String incomingValue, Instant fallbackBaseline) {
        Object patientId = snapshot.patientId();
        Object sourceId = snapshot.sourceId();
        Instant incomingTimestamp = snapshot.sourceUpdatedAt();

        Optional<FieldProvenance> provenance = provenanceStore.lockOrCreate(patientId, fieldName);
        Optional<String> currentValue = patientAccessor.getCurrentValue(patientId, fieldName);

        // Rule: patient's field is empty -> fill directly, no comparison, no audit row. Applies to
        // date_of_birth exactly the same as any other field -- there's no disagreement to hold open.
        if (currentValue.isEmpty()) {
            patientAccessor.applyValue(patientId, fieldName, incomingValue);
            refreshProvenanceIfNewer(patientId, fieldName, sourceId, incomingTimestamp, provenance);
            return new ReconciliationOutcome(fieldName, ReconciliationOutcome.Decision.FILLED_EMPTY, incomingValue);
        }

        // Rule: values already agree -> nothing to write to patient, but keep provenance current.
        // Applies to date_of_birth exactly the same as any other field, for the same reason.
        if (currentValue.get().equals(incomingValue)) {
            refreshProvenanceIfNewer(patientId, fieldName, sourceId, incomingTimestamp, provenance);
            return new ReconciliationOutcome(fieldName, ReconciliationOutcome.Decision.ALREADY_AGREED, currentValue.get());
        }

        // Real disagreement: baseline is the locked provenance's timestamp if one exists; otherwise
        // patient.updated_at (Assumption A1 -- see README.md).
        Instant baseline = provenance.map(FieldProvenance::sourceUpdatedAt)
                .orElse(fallbackBaseline);

        boolean incomingIsNewerThanConfirmedBaseline = incomingTimestamp.isAfter(baseline); // ties go to the existing value (Assumption A2)
        Instant decidedAt = Instant.now();

        if (DATE_OF_BIRTH.equals(fieldName)) {
            return reconcileDateOfBirthDisagreement(patientId, sourceId, currentValue.get(), incomingValue,
                    incomingTimestamp, incomingIsNewerThanConfirmedBaseline, decidedAt);
        }

        if (incomingIsNewerThanConfirmedBaseline) {
            patientAccessor.applyValue(patientId, fieldName, incomingValue);
            auditWriter.recordDecision(patientId, sourceId, fieldName, currentValue.get(), incomingValue,
                    IdentityConflictAuditWriter.Outcome.ACCEPTED, IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decidedAt);
            refreshProvenanceIfNewer(patientId, fieldName, sourceId, incomingTimestamp, provenance);
            return new ReconciliationOutcome(fieldName, ReconciliationOutcome.Decision.ACCEPTED_NEWER, incomingValue);
        } else {
            auditWriter.recordDecision(patientId, sourceId, fieldName, currentValue.get(), incomingValue,
                    IdentityConflictAuditWriter.Outcome.REJECTED, IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decidedAt);
            // Deliberately do NOT refresh provenance here: the losing source's timestamp is, by
            // definition, not newer than what's already recorded (or the baseline), so recording it
            // could only ever move the provenance backwards or leave it unchanged.
            return new ReconciliationOutcome(fieldName, ReconciliationOutcome.Decision.REJECTED_STALE, currentValue.get());
        }
    }

    /**
     * The {@code date_of_birth} carve-out (2026-09-26 partial reversal — see the implementation plan's
     * Decisions log): a genuine disagreement never auto-applies here, no matter how much newer the
     * incoming value is. It either gets discarded silently (not even newer than what's already
     * confirmed on {@code patient} — the ordinary recency rule would have rejected it too, so the
     * patient is never interrupted for a candidate that couldn't have won anyway) or held open as a
     * {@code PENDING} conflict for the patient to confirm via {@link #finalizePendingDateOfBirth}.
     *
     * <p><b>Assumption A3 (see README.md) — what happens if a second disagreement arrives while one is
     * already {@code PENDING}:</b> not settled by either Decisions-log entry, so this method picks a
     * defensible default rather than leaving the case unhandled. A new candidate is compared against
     * the <i>currently pending</i> candidate's timestamp, not just the confirmed baseline: newer
     * supersedes it (the stale candidate is closed out as {@code REJECTED}/{@code SYSTEM} — the system
     * is superseding it, not the patient, since they were never asked about it — and a fresh
     * {@code PENDING} conflict is opened for the new one); not-newer is discarded quietly, the same way
     * a disagreement that loses to the confirmed baseline is. Confirm this default before relying on it
     * for anything patient-visible beyond "which value ends up in the confirmation prompt."
     */
    private ReconciliationOutcome reconcileDateOfBirthDisagreement(
            Object patientId, Object sourceId, String currentValue, String incomingValue,
            Instant incomingTimestamp, boolean incomingIsNewerThanConfirmedBaseline, Instant decidedAt) {

        if (!incomingIsNewerThanConfirmedBaseline) {
            auditWriter.recordDecision(patientId, sourceId, DATE_OF_BIRTH, currentValue, incomingValue,
                    IdentityConflictAuditWriter.Outcome.REJECTED, IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decidedAt);
            return new ReconciliationOutcome(DATE_OF_BIRTH, ReconciliationOutcome.Decision.REJECTED_STALE, currentValue);
        }

        Optional<IdentityConflictAuditWriter.PendingConflict> openPending =
                auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH);

        if (openPending.isPresent()) {
            IdentityConflictAuditWriter.PendingConflict pending = openPending.get();
            if (!incomingTimestamp.isAfter(pending.sourceUpdatedAt())) {
                // Newer than the confirmed baseline, but not newer than the candidate the patient is
                // already being asked about -- discard quietly rather than replacing one unconfirmed
                // guess with an older one (Assumption A3).
                auditWriter.recordDecision(patientId, sourceId, DATE_OF_BIRTH, currentValue, incomingValue,
                        IdentityConflictAuditWriter.Outcome.REJECTED, IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decidedAt);
                return new ReconciliationOutcome(DATE_OF_BIRTH, ReconciliationOutcome.Decision.REJECTED_STALE, currentValue);
            }
            // Genuinely newer than the open candidate too -- supersede it (Assumption A3).
            auditWriter.resolvePendingConflict(patientId, DATE_OF_BIRTH,
                    IdentityConflictAuditWriter.Outcome.REJECTED, IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decidedAt);
        }

        auditWriter.openPendingConflict(patientId, sourceId, DATE_OF_BIRTH, currentValue, incomingValue,
                incomingTimestamp, decidedAt);
        // Provenance is deliberately left untouched here: it must keep reflecting the last value
        // patient.date_of_birth actually holds until the patient accepts this candidate via
        // finalizePendingDateOfBirth, not merely because it became the newest-known proposal.
        return new ReconciliationOutcome(DATE_OF_BIRTH, ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, incomingValue);
    }

    /**
     * Package-private, same reason {@link #reconcileOneFieldLocked} is: lets the contract test suite
     * exercise this directly under simulated concurrency.
     */
    ReconciliationOutcome finalizePendingDateOfBirthLocked(Object patientId, boolean acceptIncoming) {
        // Take the same per-(patientId, date_of_birth) lock every reconcile() call takes for this
        // field, so a finalize racing a concurrent reconcile() supersede attempt serializes correctly
        // instead of both reading the same pending conflict and stepping on each other.
        provenanceStore.lockOrCreate(patientId, DATE_OF_BIRTH);

        IdentityConflictAuditWriter.PendingConflict pending =
                auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH)
                        .orElseThrow(() -> new IllegalStateException(
                                "No open date_of_birth conflict is pending confirmation for patient " + patientId));

        Instant resolvedAt = Instant.now();
        if (acceptIncoming) {
            patientAccessor.applyValue(patientId, DATE_OF_BIRTH, pending.incomingValue());
            auditWriter.resolvePendingConflict(patientId, DATE_OF_BIRTH,
                    IdentityConflictAuditWriter.Outcome.ACCEPTED, IdentityConflictAuditWriter.ResolvedBy.PATIENT, resolvedAt);
            provenanceStore.recordAsFreshest(patientId, DATE_OF_BIRTH, pending.sourceId(), pending.sourceUpdatedAt());
            return new ReconciliationOutcome(DATE_OF_BIRTH, ReconciliationOutcome.Decision.ACCEPTED_BY_PATIENT, pending.incomingValue());
        } else {
            auditWriter.resolvePendingConflict(patientId, DATE_OF_BIRTH,
                    IdentityConflictAuditWriter.Outcome.REJECTED, IdentityConflictAuditWriter.ResolvedBy.PATIENT, resolvedAt);
            return new ReconciliationOutcome(DATE_OF_BIRTH, ReconciliationOutcome.Decision.REJECTED_BY_PATIENT, pending.canonicalValueBefore());
        }
    }

    private void refreshProvenanceIfNewer(
            Object patientId, String fieldName, Object sourceId, Instant incomingTimestamp,
            Optional<FieldProvenance> existing) {
        boolean shouldRefresh = existing.isEmpty()
                || !incomingTimestamp.isBefore(existing.get().sourceUpdatedAt());
        if (shouldRefresh) {
            provenanceStore.recordAsFreshest(patientId, fieldName, sourceId, incomingTimestamp);
        }
    }
}
