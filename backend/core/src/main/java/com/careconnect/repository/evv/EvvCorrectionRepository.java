package com.careconnect.repository.evv;

import com.careconnect.model.evv.EvvCorrection;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface EvvCorrectionRepository extends JpaRepository<EvvCorrection, Long> {

    List<EvvCorrection> findByOriginalRecordId(Long originalRecordId);

    List<EvvCorrection> findByCorrectedBy(Long correctedBy);

    @Query("SELECT c FROM EvvCorrection c WHERE c.approvalRequired = true AND c.approvedBy IS NULL")
    List<EvvCorrection> findPendingApprovals();

    @Query("SELECT c FROM EvvCorrection c WHERE c.originalRecord.id = :recordId ORDER BY c.correctedAt DESC")
    List<EvvCorrection> findCorrectionsByRecordId(@Param("recordId") Long recordId);

    Optional<EvvCorrection> findByCorrectedRecordId(Long correctedRecordId);
}

