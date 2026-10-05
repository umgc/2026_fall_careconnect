package com.careconnect.repository;

import com.careconnect.model.UserAIConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserAIConfigRepository extends JpaRepository<UserAIConfig, Long> {
    Optional<UserAIConfig> findByUserIdAndIsActiveTrue(Long userId);

    Optional<UserAIConfig> findByUserIdAndPatientIdAndIsActiveTrue(Long userId, Long patientId);

    List<UserAIConfig> findByUserId(Long userId);

    List<UserAIConfig> findByUserIdAndPatientId(Long userId, Long patientId);

    List<UserAIConfig> findByIsActiveTrue();

    boolean existsByUserIdAndIsActiveTrue(Long userId);
}
