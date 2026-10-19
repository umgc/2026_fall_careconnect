package com.careconnect.repository;

import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ConnectionRequestRepository extends JpaRepository<ConnectionRequest, Long> {
    List<ConnectionRequest> findByCaregiverAndStatus(User caregiver, String status);

    List<ConnectionRequest> findByPatientAndStatus(User patient, String status);

    Optional<ConnectionRequest> findByToken(String token);

    boolean existsByCaregiverAndPatientAndStatus(User caregiver, User patient, String status);
}