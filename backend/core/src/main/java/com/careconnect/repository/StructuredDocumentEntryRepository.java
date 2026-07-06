package com.careconnect.repository;

import com.careconnect.model.StructuredDocumentEntry;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface StructuredDocumentEntryRepository extends JpaRepository<StructuredDocumentEntry, Long> {

    /** Active structured entry captured from a specific uploaded file (one per file). */
    Optional<StructuredDocumentEntry> findFirstByUserFileIdAndIsActiveTrue(Long userFileId);

    /** Active structured entries linked to a patient (care-circle context). */
    List<StructuredDocumentEntry> findByPatientIdAndIsActiveTrue(Long patientId);

    /** Active structured entries linked to an employee (caregiver / staff member). */
    List<StructuredDocumentEntry> findByEmployeeUserIdAndIsActiveTrue(Long employeeUserId);

    /** All active employee-linked entries (compliance dashboard aggregation). */
    List<StructuredDocumentEntry> findByEmployeeUserIdIsNotNullAndIsActiveTrue();

    /** All active patient-linked entries (compliance dashboard aggregation). */
    List<StructuredDocumentEntry> findByPatientIdIsNotNullAndIsActiveTrue();
}
