package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrCredential;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * Persistence for {@link EhrCredential}. One active row per {@code (userId, source)}.
 */
public interface EhrCredentialRepository extends JpaRepository<EhrCredential, Long> {

    Optional<EhrCredential> findFirstByUserIdAndSourceOrderByIdDesc(Long userId, String source);

    List<EhrCredential> findByUserIdAndSource(Long userId, String source);

    boolean existsByUserIdAndSource(Long userId, String source);
}
