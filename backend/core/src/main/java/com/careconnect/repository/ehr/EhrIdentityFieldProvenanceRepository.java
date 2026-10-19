package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrIdentityFieldProvenance;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface EhrIdentityFieldProvenanceRepository
        extends JpaRepository<EhrIdentityFieldProvenance, Long> {

    /**
     * Plain lookup. Note this is <strong>not</strong> how the reconciler reads provenance: it
     * needs {@code SELECT ... FOR UPDATE} on the same transaction, which
     * {@code IdentityFieldProvenanceStore.lockOrCreate} issues explicitly. Using this method in
     * the reconciliation path would take no lock and lose the concurrency guarantee.
     */
    Optional<EhrIdentityFieldProvenance> findByPatientIdAndFieldName(Long patientId, String fieldName);

    /**
     * The reconciliation path's read: {@code SELECT ... FOR UPDATE} on the
     * {@code (patient_id, field_name)} row, held until the surrounding transaction ends.
     * <p>
     * This is the whole reason {@code ehr_identity_field_provenance} exists as a table rather than
     * a column on {@code patient} — it gives every field of every patient its own independently
     * lockable row, so two adapters reconciling different fields of the same patient never block
     * each other, while two reconciling the <em>same</em> field always serialize.
     * <p>
     * Must be called inside a transaction. Outside one, Spring's shared {@code EntityManager}
     * commits per statement, so the lock is taken and released before the caller can read anything
     * under it — no error, no lock, and the concurrency guarantee is silently gone.
     * {@code JpaIdentityFieldProvenanceStore} asserts the transaction rather than trusting callers.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from EhrIdentityFieldProvenance p "
            + "where p.patientId = :patientId and p.fieldName = :fieldName")
    Optional<EhrIdentityFieldProvenance> lockByPatientIdAndFieldName(
            @Param("patientId") Long patientId, @Param("fieldName") String fieldName);
}
