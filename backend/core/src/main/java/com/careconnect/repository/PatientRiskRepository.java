package com.careconnect.repository;

import com.careconnect.model.PatientRisk;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PatientRiskRepository extends JpaRepository<PatientRisk, Long> {
    List<PatientRisk> findByPatientIdOrderByFlaggedAtDesc(Long patientId);

    Optional<PatientRisk> findByPatientIdAndRiskTypeId(Long patientId, Long riskTypeId);

    boolean existsByPatientIdAndRiskTypeId(Long patientId, Long riskTypeId);
}
