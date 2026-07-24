package com.careconnect.repository;

import com.careconnect.model.PostCallTranscriptionJob;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface PostCallTranscriptionJobRepository
        extends JpaRepository<PostCallTranscriptionJob, Long> {
    Optional<PostCallTranscriptionJob> findByRecordingId(Long recordingId);
    Optional<PostCallTranscriptionJob> findByIdAndClaimToken(Long id, UUID claimToken);

    @Query(value = """
            SELECT id FROM post_call_transcription_jobs
             WHERE state IN ('READY', 'RETRYABLE', 'CLAIMED', 'RUNNING')
               AND next_attempt_at <= CURRENT_TIMESTAMP
               AND (claimed_until IS NULL OR claimed_until <= CURRENT_TIMESTAMP)
             ORDER BY next_attempt_at, id
             LIMIT 10
            """, nativeQuery = true)
    List<Long> findDueIds();

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE post_call_transcription_jobs
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

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE post_call_transcription_jobs
               SET state = :state, claim_token = NULL, claimed_until = NULL,
                   next_attempt_at = CURRENT_TIMESTAMP + (:delaySeconds * INTERVAL '1 second'),
                   last_error = :error,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :id AND claim_token = :token
            """, nativeQuery = true)
    int release(@Param("id") Long id, @Param("token") UUID token,
                @Param("state") String state, @Param("delaySeconds") long delaySeconds,
                @Param("error") String error);

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE post_call_transcription_jobs
               SET next_attempt_at = CURRENT_TIMESTAMP
             WHERE id = :id
            """, nativeQuery = true)
    int markDueNow(@Param("id") Long id);
}
