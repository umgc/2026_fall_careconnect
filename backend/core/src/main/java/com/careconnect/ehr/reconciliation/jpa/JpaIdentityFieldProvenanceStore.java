package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.FieldProvenance;
import com.careconnect.ehr.reconciliation.IdentityFieldProvenanceStore;
import com.careconnect.model.ehr.EhrIdentityFieldProvenance;
import com.careconnect.repository.ehr.EhrIdentityFieldProvenanceRepository;
import jakarta.persistence.EntityManager;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Objects;
import java.util.Optional;

/**
 * The PostgreSQL-backed {@link IdentityFieldProvenanceStore} — the piece the whole reconciliation
 * concurrency guarantee rests on.
 *
 * <h2>What lockOrCreate has to do, and why it is not one statement</h2>
 * It must return with the {@code (patient_id, field_name)} row locked <em>for the rest of the
 * caller's transaction</em>, whether or not that row already existed. Those two cases pull in
 * opposite directions:
 * <ul>
 *   <li>{@code SELECT ... FOR UPDATE} locks a row that exists. Against a row that does not exist it
 *       matches nothing and therefore locks nothing — it returns an empty result perfectly happily,
 *       which is exactly the silent no-lock this class exists to prevent.</li>
 *   <li>A plain {@code INSERT} creates the row, but two adapters touching a patient's field for the
 *       first time will both find nothing and both insert. One of them hits
 *       {@code uq_ehr_identity_field_provenance_patient_field}.</li>
 * </ul>
 *
 * <p>The usual fix — catch the constraint violation and re-select — <strong>does not work on
 * PostgreSQL</strong>. A constraint violation there aborts the entire transaction, not just the
 * failing statement: every subsequent statement fails with "current transaction is aborted" until
 * rollback. The caller's transaction wraps this field's whole reconciliation (the patient read, the
 * conditional write, the audit row), so catching the violation would leave us holding a transaction
 * that can no longer do anything. The catch block would look like it recovered, and would not.
 *
 * <p>So the sequence is: lock; only if nothing was there, {@code INSERT ... ON CONFLICT
 * (patient_id, field_name) DO NOTHING}; then lock again. {@code ON CONFLICT DO NOTHING} raises no
 * error, so the transaction stays usable. When a concurrent transaction has already inserted the
 * same key but not yet committed, PostgreSQL blocks our insert until that one resolves and then
 * does nothing, and the second lock attempt picks up its committed row. That second attempt is what
 * takes the lock in the created case — the insert alone locks only the row we actually wrote, which
 * under {@code DO NOTHING} may be no row at all.
 *
 * <p>The lock-first ordering, rather than insert-then-lock unconditionally, matters for write
 * volume: the row is created once per patient per field and then read on every sync thereafter, so
 * the steady state must not attempt a write.
 *
 * <h2>Empty provenance is not a missing row</h2>
 * A row is created with {@code source_id} and {@code source_updated_at} null, purely so there is
 * something to lock. {@link #lockOrCreate} returns {@link Optional#empty()} for it, which the
 * reconciler reads as "no source has established provenance for this field yet" and answers by
 * falling back to the patient record's own timestamp (Assumption A1). Returning a
 * {@link FieldProvenance} holding nulls instead would turn that fallback into a
 * {@code NullPointerException} deep inside a timestamp comparison.
 *
 * <h2>Transaction requirement</h2>
 * Both methods assert an active transaction rather than assuming one. Outside a transaction,
 * Spring's shared {@code EntityManager} runs each statement in its own auto-committed unit: the
 * {@code FOR UPDATE} is issued, the lock is taken, and the lock is released before the method even
 * returns. Nothing fails and nothing logs, but the serialization the reconciler depends on is
 * simply absent. That failure is invisible in production and invisible to any single-threaded test,
 * which is why it is worth an explicit check at the boundary.
 */
public class JpaIdentityFieldProvenanceStore implements IdentityFieldProvenanceStore {

    /**
     * Idempotent placeholder insert. The conflict target names the columns of
     * {@code uq_ehr_identity_field_provenance_patient_field}; if that index is ever dropped or
     * renamed, this statement starts failing loudly rather than silently losing its race
     * protection, which is the correct direction for that particular mistake to fail in.
     */
    private static final String INSERT_PLACEHOLDER_SQL =
            "INSERT INTO ehr_identity_field_provenance "
                    + "(patient_id, field_name, source_id, source_updated_at, created_at, updated_at) "
                    + "VALUES (:patientId, :fieldName, NULL, NULL, :now, :now) "
                    + "ON CONFLICT (patient_id, field_name) DO NOTHING";

    private final EhrIdentityFieldProvenanceRepository repository;
    private final EntityManager entityManager;

    public JpaIdentityFieldProvenanceStore(
            EhrIdentityFieldProvenanceRepository repository, EntityManager entityManager) {
        this.repository = Objects.requireNonNull(repository, "repository");
        this.entityManager = Objects.requireNonNull(entityManager, "entityManager");
    }

    @Override
    public Optional<FieldProvenance> lockOrCreate(Long patientId, String fieldName) {
        requireTransaction("lockOrCreate");
        Long resolvedPatientId = Objects.requireNonNull(patientId, "patientId");
        String resolvedFieldName = requireFieldName(fieldName);

        Optional<EhrIdentityFieldProvenance> locked =
                repository.lockByPatientIdAndFieldName(resolvedPatientId, resolvedFieldName);

        if (locked.isEmpty()) {
            insertPlaceholder(resolvedPatientId, resolvedFieldName);
            locked = repository.lockByPatientIdAndFieldName(resolvedPatientId, resolvedFieldName);
            if (locked.isEmpty()) {
                // Unreachable short of the unique index being absent: the insert either created the
                // row or found a committed one. Loud, rather than a silently unlocked path.
                throw new IllegalStateException(
                        "No ehr_identity_field_provenance row for (patient " + resolvedPatientId
                                + ", field " + resolvedFieldName
                                + ") after INSERT ... ON CONFLICT DO NOTHING. Check that "
                                + "uq_ehr_identity_field_provenance_patient_field exists.");
            }
        }

        return toProvenance(locked.get());
    }

    @Override
    public void recordAsFreshest(
            Long patientId, String fieldName, Long sourceId, Instant sourceUpdatedAt) {
        requireTransaction("recordAsFreshest");
        Long resolvedPatientId = Objects.requireNonNull(patientId, "patientId");
        String resolvedFieldName = requireFieldName(fieldName);
        Long resolvedSourceId = Objects.requireNonNull(sourceId, "sourceId");
        Objects.requireNonNull(sourceUpdatedAt, "sourceUpdatedAt");

        // Re-taking the lock is re-entrant within this transaction — PostgreSQL row locks are held
        // by transaction, not by statement — so this costs a re-read and can never block on
        // ourselves. It also means the method writes to a locked row even if some future caller
        // reaches it without going through lockOrCreate first.
        EhrIdentityFieldProvenance row = repository
                .lockByPatientIdAndFieldName(resolvedPatientId, resolvedFieldName)
                .orElseThrow(() -> new IllegalStateException(
                        "recordAsFreshest called for (patient " + resolvedPatientId + ", field "
                                + resolvedFieldName
                                + ") with no provenance row; lockOrCreate must run first"));

        row.setSourceId(resolvedSourceId);
        row.setSourceUpdatedAt(sourceUpdatedAt);

        // Flush while the lock is still held. Without this the UPDATE lands whenever the persistence
        // context happens to flush — still inside the transaction, so still correct today, but it
        // moves the write away from the code that reasons about it and makes any later change to
        // lock ordering much harder to reason about than it needs to be.
        entityManager.flush();
    }

    private void insertPlaceholder(Long patientId, String fieldName) {
        LocalDateTime now = LocalDateTime.now();
        entityManager.createNativeQuery(INSERT_PLACEHOLDER_SQL)
                .setParameter("patientId", patientId)
                .setParameter("fieldName", fieldName)
                .setParameter("now", now)
                .executeUpdate();
    }

    /**
     * Null in either column means the row exists only to be locked. The two are written together
     * and would only ever be half-populated through corruption, so reading that as "no provenance"
     * is the interpretation that cannot produce a wrong winner.
     */
    private static Optional<FieldProvenance> toProvenance(EhrIdentityFieldProvenance row) {
        if (row.getSourceId() == null || row.getSourceUpdatedAt() == null) {
            return Optional.empty();
        }
        return Optional.of(new FieldProvenance(row.getSourceId(), row.getSourceUpdatedAt()));
    }

    private static void requireTransaction(String method) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException(
                    "IdentityFieldProvenanceStore." + method + " requires an active transaction; "
                            + "without one the row lock is released before it can protect anything. "
                            + "Call it through TransactionRunner, as RecencyWinsIdentityReconciler does.");
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
