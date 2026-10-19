package com.careconnect.repository.evv;

import com.careconnect.model.evv.EvvRecord;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

@Repository
public interface EvvRecordRepository extends JpaRepository<EvvRecord, Long> {

    @Query("SELECT e FROM EvvRecord e JOIN FETCH e.patient WHERE e.caregiverId = :caregiverId AND e.status = :status")
    List<EvvRecord> findByCaregiverIdAndStatus(@Param("caregiverId") Long caregiverId, @Param("status") String status);

    @Query("SELECT e FROM EvvRecord e JOIN FETCH e.patient WHERE e.status = :status")
    List<EvvRecord> findByStatus(@Param("status") String status);

    @Query("SELECT e FROM EvvRecord e JOIN FETCH e.patient WHERE e.status = :status AND e.stateCode = :stateCode")
    List<EvvRecord> findByStatusAndStateCode(@Param("status") String status, @Param("stateCode") String stateCode);

    @Query("SELECT e FROM EvvRecord e JOIN FETCH e.patient WHERE e.id = :id")
    java.util.Optional<EvvRecord> findByIdWithPatient(@Param("id") Long id);

    List<EvvRecord> findByPatientMaNumber(String maNumber);

    List<EvvRecord> findByServiceType(String serviceType);

    List<EvvRecord> findByDateOfServiceBetween(LocalDate startDate, LocalDate endDate);

    List<EvvRecord> findByStateCode(String stateCode);

    List<EvvRecord> findByIsOfflineTrue();

    List<EvvRecord> findBySyncStatus(String syncStatus);

    List<EvvRecord> findByIsCorrectedTrue();

    List<EvvRecord> findByOriginalRecordId(Long originalRecordId);

    @Query(value = "SELECT DISTINCT e FROM EvvRecord e LEFT JOIN FETCH e.patient p WHERE " +
            "(:patientName IS NULL OR :patientName = '' OR LOWER(CONCAT(COALESCE(p.firstName, ''), ' ', COALESCE(p.lastName, ''))) LIKE LOWER(CONCAT('%', :patientName, '%'))) AND " +
            "(:serviceType IS NULL OR :serviceType = '' OR LOWER(e.serviceType) LIKE LOWER(CONCAT('%', :serviceType, '%'))) AND " +
            "(:patientId IS NULL OR p.id = :patientId) AND " +
            "(:caregiverId IS NULL OR e.caregiverId = :caregiverId) AND " +
            "(:startDate IS NULL OR e.dateOfService >= :startDate) AND " +
            "(:endDate IS NULL OR e.dateOfService <= :endDate) AND " +
            "(:stateCode IS NULL OR :stateCode = '' OR e.stateCode = :stateCode) AND " +
            "(:status IS NULL OR :status = '' OR e.status = :status)",
            countQuery = "SELECT COUNT(DISTINCT e) FROM EvvRecord e LEFT JOIN e.patient p WHERE " +
                    "(:patientName IS NULL OR :patientName = '' OR LOWER(CONCAT(COALESCE(p.firstName, ''), ' ', COALESCE(p.lastName, ''))) LIKE LOWER(CONCAT('%', :patientName, '%'))) AND " +
                    "(:serviceType IS NULL OR :serviceType = '' OR LOWER(e.serviceType) LIKE LOWER(CONCAT('%', :serviceType, '%'))) AND " +
                    "(:patientId IS NULL OR p.id = :patientId) AND " +
                    "(:caregiverId IS NULL OR e.caregiverId = :caregiverId) AND " +
                    "(:startDate IS NULL OR e.dateOfService >= :startDate) AND " +
                    "(:endDate IS NULL OR e.dateOfService <= :endDate) AND " +
                    "(:stateCode IS NULL OR :stateCode = '' OR e.stateCode = :stateCode) AND " +
                    "(:status IS NULL OR :status = '' OR e.status = :status)")
    Page<EvvRecord> searchRecords(@Param("patientName") String patientName,
                                  @Param("serviceType") String serviceType,
                                  @Param("patientId") Long patientId,
                                  @Param("caregiverId") Long caregiverId,
                                  @Param("startDate") LocalDate startDate,
                                  @Param("endDate") LocalDate endDate,
                                  @Param("stateCode") String stateCode,
                                  @Param("status") String status,
                                  Pageable pageable);

    @Query("SELECT e FROM EvvRecord e WHERE e.eorApprovalRequired = true AND e.eorApprovedBy IS NULL")
    List<EvvRecord> findPendingEorApprovals();

    @Query("SELECT e FROM EvvRecord e WHERE e.caregiverId = :caregiverId AND e.createdAt >= :since")
    List<EvvRecord> findByCaregiverSince(@Param("caregiverId") Long caregiverId, @Param("since") OffsetDateTime since);

    @Query("SELECT e FROM EvvRecord e JOIN FETCH e.patient WHERE e.id IN :ids")
    List<EvvRecord> findAllByIdWithPatient(@Param("ids") java.util.List<Long> ids);
}
