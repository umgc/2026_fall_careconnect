package com.careconnect.repository;

import com.careconnect.model.CallRecording;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface CallRecordingRepository
        extends JpaRepository<CallRecording, Long> {

    /**
     * Returns the most recent recording for a call.
     *
     * @param callId call identifier
     * @return most recent recording, when present
     */
    Optional<CallRecording> findTopByCallIdOrderByStartedAtDesc(String callId);

    @Query(value = """
            SELECT * FROM call_recordings
             WHERE call_id = :callId
               AND lifecycle_status IN
                   ('RESERVED', 'STARTING', 'ACTIVE', 'STOP_CLAIMED',
                    'STOP_RETRYABLE', 'FINALIZE_RETRYABLE', 'PURGE_PENDING')
             ORDER BY generation DESC
             LIMIT 1
            """, nativeQuery = true)
    Optional<CallRecording> findActiveByCallId(@Param("callId") String callId);

    /**
     * Reserves the sole active generation under a transaction-scoped advisory lock.
     * A zero return means another node already owns the call.
     */
    @Modifying
    @Transactional
    @Query(value = """
            WITH locked AS (
                SELECT pg_advisory_xact_lock(hashtext(:callId))
            ), next_generation AS (
                SELECT COALESCE(MAX(generation), 0) + 1 AS value
                  FROM call_recordings, locked
                 WHERE call_id = :callId
            )
            INSERT INTO call_recordings
                (call_id, generation, purpose, lifecycle_status, status,
                 initiated_by_user_id, owner_user_id, consented_at,
                 consented_by_user_id, purge_state, started_at, created_at, updated_at)
            SELECT :callId, value, :purpose, 'RESERVED', 'STARTED',
                   :ownerUserId, :ownerUserId,
                   CASE WHEN :consented THEN (now() AT TIME ZONE 'UTC') ELSE NULL END,
                   CASE WHEN :consented THEN :ownerUserId ELSE NULL END,
                   'NONE',
                   (now() AT TIME ZONE 'UTC'),
                   (now() AT TIME ZONE 'UTC'),
                   (now() AT TIME ZONE 'UTC')
              FROM next_generation
            ON CONFLICT DO NOTHING
            """, nativeQuery = true)
    int reserveActiveGeneration(
            @Param("callId") String callId,
            @Param("purpose") String purpose,
            @Param("ownerUserId") Long ownerUserId,
            @Param("consented") boolean consented);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            UPDATE call_recordings
               SET lifecycle_status = 'STOP_CLAIMED',
                   claim_token = :claimToken,
                   claim_lease_until =
                       CURRENT_TIMESTAMP + (:leaseSeconds * INTERVAL '1 second'),
                   attempt_count = attempt_count + 1,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :recordingId
               AND lifecycle_status IN
                   ('ACTIVE', 'STOP_RETRYABLE', 'FINALIZE_RETRYABLE', 'PURGE_PENDING')
               AND (claim_lease_until IS NULL OR claim_lease_until <= CURRENT_TIMESTAMP)
            """, nativeQuery = true)
    int claimForStop(
            @Param("recordingId") Long recordingId,
            @Param("claimToken") UUID claimToken,
            @Param("leaseSeconds") long leaseSeconds);

    @Modifying
    @Transactional
    @Query(value = """
            UPDATE call_recordings
               SET lifecycle_status = :status,
                   claim_token = NULL, claim_lease_until = NULL,
                   next_retry_at =
                       CURRENT_TIMESTAMP + (:retrySeconds * INTERVAL '1 second'),
                   last_error = :lastError, error_message = :lastError,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :recordingId AND claim_token = :claimToken
            """, nativeQuery = true)
    int releaseClaimForRetry(
            @Param("recordingId") Long recordingId,
            @Param("claimToken") UUID claimToken,
            @Param("status") String status,
            @Param("retrySeconds") long retrySeconds,
            @Param("lastError") String lastError);

    /**
     * Returns all recordings for a call, newest first.
     *
     * @param callId call identifier
     * @return matching recordings
     *     in descending start order
     */
    List<CallRecording> findByCallIdOrderByStartedAtDesc(String callId);

    /**
     * Returns recordings initiated by a user, newest first.
     *
     * @param userId initiating user identifier
     * @return matching recordings
     *     in descending start order
     */
    List<CallRecording> findByInitiatedByUserIdOrderByStartedAtDesc(
            Long userId
    );

    /**
     * Returns recordings with a status, newest first.
     *
     * @param status recording status
     * @return matching recordings
     *     in descending start order
     */
    List<CallRecording> findByStatusOrderByStartedAtDesc(String status);

    /**
     * Returns up to 100 recordings with a status.
     *
     * @param status recording status
     * @return up to 100 matching recordings in
     *     descending start order
     */
    List<CallRecording> findTop100ByStatusOrderByStartedAtDesc(String status);

    /**
     * Returns the most recent system-initiated (auto) recording for a call.
     * System recordings have a null initiatedByUserId.
     *
     * @param callId call identifier
     * @return most recent system recording, when present
     */
    Optional<CallRecording> findTopByCallIdAndInitiatedByUserIdIsNullOrderByStartedAtDesc(
            String callId);

    /**
     * Deletes recordings for a call.
     *
     * @param callId call identifier
     * @return number of deleted rows
     */
    long deleteByCallId(String callId);
}
