package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter;
import com.careconnect.model.ehr.EhrConflictResolver;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.util.Objects;
import java.util.Optional;

/**
 * Writes the {@code ehr_identity_conflict} trail — every identity decision the reconciler makes, and
 * the one kind it defers to the patient.
 *
 * <h2>Both outcomes are recorded, not just the interesting one</h2>
 * A {@code REJECTED} row is written even though nothing changed. That is the point: "this source
 * offered a different date of birth and we discarded it" is the fact someone needs months later when
 * a crosswalk turns out to have been wrong, and it is unrecoverable if only accepted values were
 * kept. A silent rejection and a sync that never ran look identical in the data.
 *
 * <h2>The database owns the rules, and this class stays inside them</h2>
 * Three constraints make the design unfalsifiable from Java, and this class is written to satisfy
 * them rather than to duplicate them:
 * <ul>
 *   <li>{@code ck_ehr_identity_conflict_pending_dob} — only {@code date_of_birth} may be
 *       {@code PENDING}. Every other field is decided in the transaction that detected it.</li>
 *   <li>{@code ck_ehr_identity_conflict_resolution} — {@code resolved_at} and {@code resolved_by} are
 *       both null on a {@code PENDING} row and both set on any other. There is no half-resolved
 *       state to represent.</li>
 *   <li>{@code uq_ehr_identity_conflict_open} — a partial unique index over
 *       {@code (patient_id, field_name) WHERE status = 'PENDING'}. At most one open conflict per
 *       field, so a patient is never asked two questions about the same thing.</li>
 * </ul>
 *
 * <p>{@link #openPendingConflict} therefore does not check for an existing open row before inserting.
 * A check would be a race — another transaction can open one between the check and the insert — and
 * the index is what actually prevents it. The insert is flushed immediately so the violation surfaces
 * here, at the call that caused it, rather than at an arbitrary later flush.
 *
 * <h2>Why every method demands a transaction</h2>
 * An audit row is only meaningful if it commits with the decision it records. A {@code REJECTED} row
 * that survives a rolled-back reconciliation is a lie about what happened; an {@code ACCEPTED} row
 * that rolls back while the {@code patient} write commits is worse. Outside a transaction, Spring's
 * shared {@code EntityManager} auto-commits per statement and both become possible, silently. The
 * reconciler always supplies one via {@code TransactionRunner}; this asserts it rather than trusting
 * it.
 */
public class JpaIdentityConflictAuditWriter implements IdentityConflictAuditWriter {

    private final EhrIdentityConflictRepository repository;

    public JpaIdentityConflictAuditWriter(EhrIdentityConflictRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository");
    }

    @Override
    public void recordDecision(
            Long patientId,
            Long sourceId,
            String fieldName,
            String canonicalValueBefore,
            String incomingValue,
            Instant sourceUpdatedAt,
            Outcome outcome,
            ResolvedBy resolvedBy,
            Instant detectedAndResolvedAt) {
        requireTransaction("recordDecision");
        Objects.requireNonNull(outcome, "outcome");
        Objects.requireNonNull(resolvedBy, "resolvedBy");
        Objects.requireNonNull(sourceUpdatedAt, "sourceUpdatedAt");
        Objects.requireNonNull(detectedAndResolvedAt, "detectedAndResolvedAt");

        EhrIdentityConflict row = EhrIdentityConflict.builder()
                .patientId(Objects.requireNonNull(patientId, "patientId"))
                .sourceId(Objects.requireNonNull(sourceId, "sourceId"))
                .fieldName(requireFieldName(fieldName))
                .canonicalValueBefore(canonicalValueBefore)
                .incomingValue(incomingValue)
                .sourceUpdatedAt(sourceUpdatedAt)
                .status(toStatus(outcome))
                // Detected and resolved in the same breath, so one timestamp serves as both. That is
                // not a shortcut: for every field but date_of_birth there is no interval between the
                // two, and recording a fabricated gap would misrepresent the algorithm.
                .detectedAt(detectedAndResolvedAt)
                .resolvedAt(detectedAndResolvedAt)
                .resolvedBy(toResolver(resolvedBy))
                .build();

        repository.saveAndFlush(row);
    }

    @Override
    public void openPendingConflict(
            Long patientId,
            Long sourceId,
            String fieldName,
            String canonicalValueBefore,
            String incomingValue,
            Instant sourceUpdatedAt,
            Instant detectedAt) {
        requireTransaction("openPendingConflict");
        Objects.requireNonNull(sourceUpdatedAt, "sourceUpdatedAt");
        Objects.requireNonNull(detectedAt, "detectedAt");

        EhrIdentityConflict row = EhrIdentityConflict.builder()
                .patientId(Objects.requireNonNull(patientId, "patientId"))
                .sourceId(Objects.requireNonNull(sourceId, "sourceId"))
                .fieldName(requireFieldName(fieldName))
                .canonicalValueBefore(canonicalValueBefore)
                .incomingValue(incomingValue)
                .sourceUpdatedAt(sourceUpdatedAt)
                .status(EhrConflictStatus.PENDING)
                .detectedAt(detectedAt)
                // Left null deliberately, and enforced by ck_ehr_identity_conflict_resolution: a
                // pending conflict has no resolution yet, and there is no placeholder that would not
                // be a claim about a decision nobody has made.
                .resolvedAt(null)
                .resolvedBy(null)
                .build();

        // Flushed here so uq_ehr_identity_conflict_open rejects a duplicate at this call rather than
        // at some later flush inside unrelated code. No pre-check: it would race, and the index is
        // the thing that actually decides.
        repository.saveAndFlush(row);
    }

    @Override
    public Optional<PendingConflict> currentPendingConflict(Long patientId, String fieldName) {
        return repository
                .findByPatientIdAndFieldNameAndStatus(
                        Objects.requireNonNull(patientId, "patientId"),
                        requireFieldName(fieldName),
                        EhrConflictStatus.PENDING)
                .map(row -> new PendingConflict(
                        row.getSourceId(),
                        row.getCanonicalValueBefore(),
                        row.getIncomingValue(),
                        row.getSourceUpdatedAt(),
                        row.getDetectedAt()));
    }

    @Override
    public boolean patientHasDeclined(Long patientId, String fieldName, String incomingValue) {
        return repository.existsByPatientIdAndFieldNameAndIncomingValueAndStatusAndResolvedBy(
                Objects.requireNonNull(patientId, "patientId"),
                requireFieldName(fieldName),
                Objects.requireNonNull(incomingValue, "incomingValue"),
                EhrConflictStatus.REJECTED,
                EhrConflictResolver.PATIENT);
    }

    /**
     * Resolves the open row in place rather than writing a second one. The pending row <em>is</em> the
     * record of this conflict; closing it by insert would leave the original looking permanently
     * unanswered, and would immediately collide with the open-conflict index the moment the same
     * field disagreed again.
     */
    @Override
    public void resolvePendingConflict(
            Long patientId, String fieldName, Outcome outcome, ResolvedBy resolvedBy, Instant resolvedAt) {
        requireTransaction("resolvePendingConflict");
        Objects.requireNonNull(outcome, "outcome");
        Objects.requireNonNull(resolvedBy, "resolvedBy");
        Objects.requireNonNull(resolvedAt, "resolvedAt");

        Long resolvedPatientId = Objects.requireNonNull(patientId, "patientId");
        String resolvedFieldName = requireFieldName(fieldName);

        EhrIdentityConflict row = repository
                .findByPatientIdAndFieldNameAndStatus(
                        resolvedPatientId, resolvedFieldName, EhrConflictStatus.PENDING)
                .orElseThrow(() -> new IllegalStateException(
                        "No open PENDING conflict for patient " + resolvedPatientId + " field "
                                + resolvedFieldName + " to resolve"));

        row.setStatus(toStatus(outcome));
        row.setResolvedBy(toResolver(resolvedBy));
        row.setResolvedAt(resolvedAt);

        // Both resolution columns move with status in one flush. Flushing between them would briefly
        // present a row that ck_ehr_identity_conflict_resolution forbids.
        repository.saveAndFlush(row);
    }

    private static EhrConflictStatus toStatus(Outcome outcome) {
        return outcome == Outcome.ACCEPTED ? EhrConflictStatus.ACCEPTED : EhrConflictStatus.REJECTED;
    }

    private static EhrConflictResolver toResolver(ResolvedBy resolvedBy) {
        return resolvedBy == ResolvedBy.PATIENT ? EhrConflictResolver.PATIENT : EhrConflictResolver.SYSTEM;
    }

    private static void requireTransaction(String method) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException(
                    "IdentityConflictAuditWriter." + method + " requires an active transaction, so the "
                            + "audit row commits or rolls back with the decision it records.");
        }
    }

    private static String requireFieldName(String fieldName) {
        Objects.requireNonNull(fieldName, "fieldName");
        if (fieldName.isBlank()) {
            throw new IllegalArgumentException("fieldName must not be blank");
        }
        return fieldName;
    }
}
