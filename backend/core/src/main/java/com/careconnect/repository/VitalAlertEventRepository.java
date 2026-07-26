package com.careconnect.repository;

import com.careconnect.model.VitalAlertEvent;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface VitalAlertEventRepository extends JpaRepository<VitalAlertEvent, Long> {
    List<VitalAlertEvent> findByPatientIdOrderByOccurredAtDesc(Long patientId, Pageable pageable);
}
