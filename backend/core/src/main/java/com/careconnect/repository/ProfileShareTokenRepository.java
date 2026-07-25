package com.careconnect.repository;

import com.careconnect.model.ProfileShareToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface ProfileShareTokenRepository extends JpaRepository<ProfileShareToken, Long> {

    Optional<ProfileShareToken> findByTokenLookup(String tokenLookup);

    List<ProfileShareToken> findByPatientUserIdOrderByCreatedAtDesc(Long patientUserId);

    @Query("""
        SELECT CASE WHEN COUNT(t) > 0 THEN true ELSE false END
        FROM ProfileShareToken t
        WHERE t.patientUserId = :patientUserId
          AND t.status = com.careconnect.model.ProfileShareToken.Status.ACTIVE
          AND t.expiresAt > :now
        """)
    boolean existsActiveToken(@Param("patientUserId") Long patientUserId,
                              @Param("now") LocalDateTime now);

    @Query("""
        SELECT t FROM ProfileShareToken t
        WHERE t.patientUserId = :patientUserId
          AND t.status = com.careconnect.model.ProfileShareToken.Status.ACTIVE
          AND t.expiresAt > :now
        """)
    Optional<ProfileShareToken> findActiveToken(@Param("patientUserId") Long patientUserId,
                                                @Param("now") LocalDateTime now);
}
