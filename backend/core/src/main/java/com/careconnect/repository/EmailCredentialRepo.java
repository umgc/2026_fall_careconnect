package com.careconnect.repository;

import com.careconnect.model.EmailCredential;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface EmailCredentialRepo extends JpaRepository<EmailCredential, Long> {
    Optional<EmailCredential> findFirstByUserIdAndProviderOrderByIdDesc(String userId, EmailCredential.Provider provider);
}
