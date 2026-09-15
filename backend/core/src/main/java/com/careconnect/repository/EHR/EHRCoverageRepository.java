package com.careconnect.repository;

import com.careconnect.model.EHRCoverage;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.List;

public interface EHRCoverageRepository extends JpaRepository<EHRCoverage, Long> {
    List<EHRCoverage> findByPatientIdOrderByCreatedAtDesc(Long patientId);

    Optional<EHRCoverage> findTopByPatientIdOrderByCreatedAtDesc(Long patientId);

}
