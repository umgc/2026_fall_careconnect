// com.careconnect.repository.CheckInRepository
package com.careconnect.repository;

import com.careconnect.model.CheckIn;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.List;

public interface CheckInRepository extends JpaRepository<CheckIn, Long> {
    List<CheckIn> findByPatientIdOrderByCreatedAtDesc(Long patientId);

    Optional<CheckIn> findTopByPatientIdOrderByCreatedAtDesc(Long patientId);

    @Query("""
            SELECT c
            FROM CheckIn c
            WHERE c.patient.id = :patientId
              AND (:startDate IS NULL OR c.createdAt >= :startDate)
              AND (:endDate IS NULL OR c.createdAt <= :endDate)
              AND (
                :status IS NULL
                OR (:status = 'draft' AND c.submittedAt IS NULL)
                OR (:status = 'submitted' AND c.submittedAt IS NOT NULL AND c.reviewedAt IS NULL)
                OR (:status = 'reviewed' AND c.reviewedAt IS NOT NULL)
              )
            """)
    Page<CheckIn> findByPatientIdWithFilters(
            @Param("patientId") Long patientId,
            @Param("status") String status,
            @Param("startDate") OffsetDateTime startDate,
            @Param("endDate") OffsetDateTime endDate,
            Pageable pageable
    );
}
