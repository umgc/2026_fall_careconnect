package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrIdentityFieldProvenance;
import org.springframework.data.jpa.repository.JpaRepository;

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
}
