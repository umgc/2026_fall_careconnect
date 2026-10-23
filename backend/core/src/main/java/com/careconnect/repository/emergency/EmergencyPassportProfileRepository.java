package com.careconnect.repository.emergency;

import com.careconnect.model.emergency.EmergencyPassportProfile;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface EmergencyPassportProfileRepository extends JpaRepository<EmergencyPassportProfile, Long> {

    /** Empty until the patient first saves a passport field. */
    Optional<EmergencyPassportProfile> findByPatientId(Long patientId);
}
