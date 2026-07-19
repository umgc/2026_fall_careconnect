package com.careconnect.repository;

import com.careconnect.model.CallSession;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface CallSessionRepository extends JpaRepository<CallSession, Long> {
    Optional<CallSession> findByCallId(String callId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT session FROM CallSession session WHERE session.callId = :callId")
    Optional<CallSession> findByCallIdForLifecycle(@Param("callId") String callId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT session FROM CallSession session WHERE session.id = :sessionId")
    Optional<CallSession> findByIdForLifecycle(@Param("sessionId") Long sessionId);

    @Lock(LockModeType.PESSIMISTIC_READ)
    @Query("SELECT session FROM CallSession session WHERE session.callId = :callId")
    Optional<CallSession> findByCallIdForIndexing(@Param("callId") String callId);

    @Modifying
    @Query(value = """
            INSERT INTO call_sessions
              (call_id, patient_id, created_by_user_id, scheduled_visit_id, status, created_at, updated_at)
            VALUES
              (:callId, :patientId, :creatorId, :scheduledVisitId, :status, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (call_id) DO NOTHING
            """, nativeQuery = true)
    int insertIfAbsent(
            @Param("callId") String callId,
            @Param("patientId") Long patientId,
            @Param("creatorId") Long creatorId,
            @Param("scheduledVisitId") Long scheduledVisitId,
            @Param("status") String status);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallSession s
               SET s.chimeMeetingId = :meetingId, s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.callId = :callId
               AND (s.chimeMeetingId IS NULL OR s.chimeMeetingId = :meetingId)
               AND s.status IN (:created, :active)
            """)
    int persistMeetingIdIfAbsent(
            @Param("callId") String callId,
            @Param("meetingId") String meetingId,
            @Param("created") String created,
            @Param("active") String active);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallSession s SET s.chimeMeetingId = NULL, s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.callId = :callId AND s.chimeMeetingId = :meetingId
            """)
    int clearMeetingId(
            @Param("callId") String callId, @Param("meetingId") String meetingId);

    @Modifying
    @Query("""
            UPDATE CallSession s
               SET s.status = :active, s.chimeMeetingId = COALESCE(s.chimeMeetingId, :meetingId),
                   s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status IN (:created, :active)
            """)
    int activateIfJoinable(
            @Param("sessionId") Long sessionId,
            @Param("meetingId") String meetingId,
            @Param("created") String created,
            @Param("active") String active);

    @Modifying
    @Query(value = """
            UPDATE call_sessions
               SET status = :terminating,
                   termination_claim_id = :claimId,
                   termination_claimed_by_user_id = :claimedByUserId,
                   termination_lease_until =
                       CURRENT_TIMESTAMP + (:leaseSeconds * INTERVAL '1 second'),
                   termination_attempt_count = termination_attempt_count + 1,
                   termination_next_retry_at = NULL,
                   termination_last_error = NULL,
                   termination_notify_user_ids = :notifyUserIds,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId AND status IN (:created, :active)
            """, nativeQuery = true)
    int beginTermination(
            @Param("sessionId") Long sessionId,
            @Param("created") String created,
            @Param("active") String active,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("claimedByUserId") Long claimedByUserId,
            @Param("leaseSeconds") long leaseSeconds,
            @Param("notifyUserIds") String notifyUserIds);

    @Modifying
    @Query(value = """
            UPDATE call_sessions
               SET termination_claim_id = :claimId,
                   termination_claimed_by_user_id = :claimedByUserId,
                   termination_lease_until =
                       CURRENT_TIMESTAMP + (:leaseSeconds * INTERVAL '1 second'),
                   termination_attempt_count = termination_attempt_count + 1,
                   termination_next_retry_at = NULL,
                   termination_last_error = NULL,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND (termination_lease_until IS NULL
                    OR termination_lease_until <= CURRENT_TIMESTAMP)
               AND (termination_next_retry_at IS NULL
                    OR termination_next_retry_at <= CURRENT_TIMESTAMP)
            """, nativeQuery = true)
    int reclaimTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("claimedByUserId") Long claimedByUserId,
            @Param("leaseSeconds") long leaseSeconds);

    @Modifying
    @Query("""
            UPDATE CallSession s
               SET s.status = :ended, s.endedAt = CURRENT_TIMESTAMP,
                   s.terminationLeaseUntil = NULL, s.terminationNextRetryAt = NULL,
                   s.terminationLastError = NULL, s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status = :terminating
               AND s.terminationClaimId = :claimId
            """)
    int completeTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("ended") String ended,
            @Param("claimId") UUID claimId);

    @Modifying
    @Query(value = """
            UPDATE call_sessions
               SET termination_lease_until = NULL,
                   termination_next_retry_at =
                       CURRENT_TIMESTAMP + (:retrySeconds * INTERVAL '1 second'),
                   termination_last_error = :lastError,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId AND status = :terminating
               AND termination_claim_id = :claimId
            """, nativeQuery = true)
    int failTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("retrySeconds") long retrySeconds,
            @Param("lastError") String lastError);

    @Query(value = """
            SELECT id
              FROM call_sessions
             WHERE status = :terminating
               AND (termination_lease_until IS NULL
                    OR termination_lease_until <= CURRENT_TIMESTAMP)
               AND (termination_next_retry_at IS NULL
                    OR termination_next_retry_at <= CURRENT_TIMESTAMP)
             ORDER BY COALESCE(termination_next_retry_at, updated_at), id
             LIMIT :limit
            """, nativeQuery = true)
    List<Long> findDueTerminationIds(
            @Param("terminating") String terminating, @Param("limit") int limit);

    @Modifying
    @Query("""
            UPDATE CallSession s
               SET s.chimeMeetingId = COALESCE(s.chimeMeetingId, :meetingId),
                   s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.callId = :callId AND s.status = :terminating
               AND (s.chimeMeetingId IS NULL OR s.chimeMeetingId = :meetingId)
            """)
    int attachMeetingToTermination(
            @Param("callId") String callId,
            @Param("meetingId") String meetingId,
            @Param("terminating") String terminating);

    @Modifying
    @Query("""
            UPDATE CallSession s SET s.status = :cancelled, s.endedAt = CURRENT_TIMESTAMP,
                   s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status = :created
            """)
    int cancelIfNotActive(
            @Param("sessionId") Long sessionId,
            @Param("created") String created,
            @Param("cancelled") String cancelled);
}
