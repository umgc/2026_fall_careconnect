package com.careconnect.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.careconnect.model.Caregiver;
import com.careconnect.model.User;

import java.util.Optional;

public interface CaregiverRepository extends JpaRepository<Caregiver, Long> {
    Optional<Caregiver> findByUser(User user);

    Optional<Caregiver> findByUserId(Long userId);

    boolean existsByIdAndUserId(Long caregiverId, Long userId);

}