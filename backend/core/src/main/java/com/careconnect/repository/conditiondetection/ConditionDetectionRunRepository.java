package com.careconnect.repository.conditiondetection;

import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.repository.projection.ConditionDueRunProjection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

/**
 * Durable condition detection runs. The lease queries mirror
 * {@link com.careconnect.repository.PostCallTranscriptionJobRepository}.
 */
public interface ConditionDetectionRunRepository
        extends JpaRepository<ConditionDetectionRun, Long> {

    List<ConditionDetectionRun> findByCallIdOrderByIdAsc(String callId);

    Optional<ConditionDetectionRun> findByCallIdAndModelId(String callId, String modelId);

    Optional<ConditionDetectionRun> findByIdAndClaimToken(Long id, UUID claimToken);

    // "modelId" is quoted so PostgreSQL keeps its case and it matches the projection getter.
    @Query(value = """
            SELECT id AS id, model_id AS "modelId" FROM condition_detection_runs
             WHERE state IN ('READY', 'RETRYABLE', 'CLAIMED', 'RUNNING')
               AND next_attempt_at <= CURRENT_TIMESTAMP
               AND (claimed_until IS NULL OR claimed_until <= CURRENT_TIMESTAMP)
             ORDER BY next_attempt_at, id
             LIMIT 10
            """, nativeQuery = true)
    List<ConditionDueRunProjection> findDueRuns();

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE condition_detection_runs
               SET state = 'CLAIMED', claim_token = :token,
                   claimed_until = CURRENT_TIMESTAMP + (:leaseSeconds * INTERVAL '1 second'),
                   attempt_count = attempt_count + 1,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :id
               AND state IN ('READY', 'RETRYABLE', 'CLAIMED', 'RUNNING')
               AND (claimed_until IS NULL OR claimed_until <= CURRENT_TIMESTAMP)
            """, nativeQuery = true)
    int claim(@Param("id") Long id, @Param("token") UUID token,
              @Param("leaseSeconds") long leaseSeconds);

    /**
     * Makes a new run due by the database clock. {@code next_attempt_at} written from Java is
     * shifted by {@code hibernate.jdbc.time_zone=UTC} on non-UTC hosts (+4 h in EDT), which the
     * native due/claim queries would read as hours in the future.
     */
    @Modifying
    @Transactional
    @Query(value = """
            UPDATE condition_detection_runs
               SET next_attempt_at = CURRENT_TIMESTAMP
             WHERE id = :id
            """, nativeQuery = true)
    int markDueNow(@Param("id") Long id);

    /** Token-fenced release back to the queue (RETRYABLE) after a failed attempt. */
    @Modifying
    @Transactional
    @Query(value = """
            UPDATE condition_detection_runs
               SET state = 'RETRYABLE', claim_token = NULL, claimed_until = NULL,
                   next_attempt_at = CURRENT_TIMESTAMP + (:delaySeconds * INTERVAL '1 second'),
                   last_error = :error,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :id AND claim_token = :token
            """, nativeQuery = true)
    int releaseForRetry(@Param("id") Long id, @Param("token") UUID token,
                        @Param("delaySeconds") long delaySeconds,
                        @Param("error") String error);

    /**
     * Token-fenced re-queue while an input is not ready yet (for example the transcript).
     * Gives back the attempt the claim consumed, so waiting never exhausts retries.
     */
    @Modifying
    @Transactional
    @Query(value = """
            UPDATE condition_detection_runs
               SET state = 'READY', claim_token = NULL, claimed_until = NULL,
                   attempt_count = GREATEST(attempt_count - 1, 0),
                   next_attempt_at = CURRENT_TIMESTAMP + (:delaySeconds * INTERVAL '1 second'),
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :id AND claim_token = :token
            """, nativeQuery = true)
    int defer(@Param("id") Long id, @Param("token") UUID token,
              @Param("delaySeconds") long delaySeconds);
}
