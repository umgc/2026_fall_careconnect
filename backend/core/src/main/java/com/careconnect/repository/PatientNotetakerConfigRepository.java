package com.careconnect.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.careconnect.model.PatientNotetakerConfig;

@Repository
public interface PatientNotetakerConfigRepository extends JpaRepository<PatientNotetakerConfig, Long> {
    PatientNotetakerConfig findByPatientId(Long patientId);
}
