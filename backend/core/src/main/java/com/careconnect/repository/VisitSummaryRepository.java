package com.careconnect.repository;

import com.careconnect.model.VisitSummary;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface VisitSummaryRepository extends JpaRepository<VisitSummary, Long> {

    Optional<VisitSummary> findTopByVisitIdOrderByGeneratedAtDesc(String visitId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT summary FROM VisitSummary summary WHERE summary.id = :id")
    Optional<VisitSummary> findByIdForUpdate(@Param("id") Long id);
}
