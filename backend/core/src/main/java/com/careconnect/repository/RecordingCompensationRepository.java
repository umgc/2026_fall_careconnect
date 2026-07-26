package com.careconnect.repository;

import com.careconnect.model.RecordingCompensation;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface RecordingCompensationRepository
        extends JpaRepository<RecordingCompensation, Long> {

    @Query(value = """
            SELECT id FROM recording_compensation_outbox
             WHERE completed_at IS NULL
               AND next_attempt_at <= CURRENT_TIMESTAMP
               AND (claimed_until IS NULL OR claimed_until <= CURRENT_TIMESTAMP)
             ORDER BY next_attempt_at, id LIMIT :limit
            """, nativeQuery = true)
    List<Long> findDueIds(@Param("limit") int limit);

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE recording_compensation_outbox
               SET state = 'CLAIMED', claim_token = :token,
                   claimed_until = CURRENT_TIMESTAMP + (:leaseSeconds * INTERVAL '1 second'),
                   attempt_count = attempt_count + 1, updated_at = CURRENT_TIMESTAMP
             WHERE id = :id AND completed_at IS NULL
               AND (claimed_until IS NULL OR claimed_until <= CURRENT_TIMESTAMP)
            """, nativeQuery = true)
    int claim(@Param("id") Long id, @Param("token") UUID token,
              @Param("leaseSeconds") long leaseSeconds);

    Optional<RecordingCompensation> findByIdAndClaimToken(Long id, UUID claimToken);

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE recording_compensation_outbox
               SET state = 'COMPLETE', completed_at = CURRENT_TIMESTAMP,
                   claim_token = NULL, claimed_until = NULL, last_error = NULL,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :id AND claim_token = :token
            """, nativeQuery = true)
    int complete(@Param("id") Long id, @Param("token") UUID token);

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE recording_compensation_outbox
               SET state = 'RETRYABLE', claim_token = NULL, claimed_until = NULL,
                   next_attempt_at = CURRENT_TIMESTAMP + (:delaySeconds * INTERVAL '1 second'),
                   last_error = :error, updated_at = CURRENT_TIMESTAMP
             WHERE id = :id AND claim_token = :token
            """, nativeQuery = true)
    int retry(@Param("id") Long id, @Param("token") UUID token,
              @Param("delaySeconds") long delaySeconds, @Param("error") String error);
}
