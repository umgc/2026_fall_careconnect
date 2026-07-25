package com.careconnect.repository;

import com.careconnect.model.EmailCredential;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface EmailCredentialRepository extends JpaRepository<EmailCredential, Long> {

    // ✅ This method is required by UspsDigestService
    Optional<EmailCredential> findFirstByUserIdAndProvider(String userId, EmailCredential.Provider provider);

    // (Optional, but useful if you use it elsewhere)
    Optional<EmailCredential> findFirstByUserIdAndProviderOrderByIdDesc(String userId, EmailCredential.Provider provider);

    /** Latest credential for a user across all providers. */
    Optional<EmailCredential> findFirstByUserIdOrderByIdDesc(String userId);
}
