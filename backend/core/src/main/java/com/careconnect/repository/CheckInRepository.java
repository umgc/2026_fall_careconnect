// com.careconnect.repository.CheckInRepository
package com.careconnect.repository;
import com.careconnect.model.CheckIn;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.List;
public interface CheckInRepository extends JpaRepository<CheckIn, Long> {
  List<CheckIn> findByPatientIdOrderByCreatedAtDesc(Long patientId);
  Optional<CheckIn> findTopByPatientIdOrderByCreatedAtDesc(Long patientId);
}
