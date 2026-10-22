package com.careconnect.repository.emergency;

import com.careconnect.model.emergency.EmergencyPassportToken;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EmergencyPassportTokenRepository extends JpaRepository<EmergencyPassportToken, Long> {

    /** Finding the row does not authorize anything; the caller still verifies the hash. */
    Optional<EmergencyPassportToken> findByTokenLookup(String tokenLookup);

    /** A list, not an Optional: revocation must catch every active row, even one that should not exist. */
    List<EmergencyPassportToken> findByPatientIdAndStatus(Long patientId, EmergencyPassportToken.Status status);
}
