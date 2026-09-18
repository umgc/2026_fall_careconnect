package com.careconnect.repository;

import com.careconnect.model.Template;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TemplateRepository extends JpaRepository<Template, Long> {
    // Optional<List<Template>> findByPatientId(Long patientId);
}
