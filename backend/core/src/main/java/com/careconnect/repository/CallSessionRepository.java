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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("""
            UPDATE CallSession s SET s.chimeMeetingId = NULL, s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.callId = :callId AND s.chimeMeetingId = :meetingId
            """)
    int clearMeetingId(
            @Param("callId") String callId, @Param("meetingId") String meetingId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions session
               SET recording_start_elected = TRUE, updated_at = CURRENT_TIMESTAMP
             WHERE session.id = :sessionId
               AND session.recording_start_elected = FALSE
               AND (SELECT COUNT(*) FROM call_participants participant
                     WHERE participant.call_session_id = session.id
                       AND participant.status = :joined) >= :threshold
            """, nativeQuery = true)
    int electRecordingStart(
            @Param("sessionId") Long sessionId,
            @Param("joined") String joined,
            @Param("threshold") int threshold);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET status = :terminating,
                   termination_claim_id = :claimId,
                   termination_claimed_by_user_id = :claimedByUserId,
                   termination_lease_until =
                       :leaseUntil,
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
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil,
            @Param("notifyUserIds") String notifyUserIds);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_claim_id = :claimId,
                   termination_claimed_by_user_id = :claimedByUserId,
                   termination_lease_until =
                       :leaseUntil,
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
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_lease_until =
                       :leaseUntil,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND termination_claim_id = :claimId
            """, nativeQuery = true)
    int renewTerminationLease(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_sentiment_at = CURRENT_TIMESTAMP,
                   termination_lease_until =
                       :leaseUntil,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND termination_claim_id = :claimId
               AND termination_sentiment_at IS NULL
            """, nativeQuery = true)
    int markTerminationSentiment(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_summary_at = CURRENT_TIMESTAMP,
                   termination_lease_until =
                       :leaseUntil,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND termination_claim_id = :claimId
               AND termination_summary_at IS NULL
            """, nativeQuery = true)
    int markTerminationSummary(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_recording_at = CURRENT_TIMESTAMP,
                   termination_lease_until =
                       :leaseUntil,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND termination_claim_id = :claimId
               AND termination_recording_at IS NULL
            """, nativeQuery = true)
    int markTerminationRecording(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_meeting_at = CURRENT_TIMESTAMP,
                   termination_lease_until =
                       :leaseUntil,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND termination_claim_id = :claimId
               AND termination_meeting_at IS NULL
            """, nativeQuery = true)
    int markTerminationMeeting(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("leaseUntil") java.time.LocalDateTime leaseUntil);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET status = :ended,
                   ended_at = CURRENT_TIMESTAMP,
                   termination_lease_until = NULL,
                   termination_next_retry_at = NULL,
                   termination_last_error = NULL,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId
               AND status = :terminating
               AND termination_claim_id = :claimId
               AND termination_sentiment_at IS NOT NULL
               AND termination_summary_at IS NOT NULL
               AND termination_recording_at IS NOT NULL
               AND termination_meeting_at IS NOT NULL
            """, nativeQuery = true)
    int completeTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("ended") String ended,
            @Param("claimId") UUID claimId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE call_sessions
               SET termination_lease_until = NULL,
                   termination_next_retry_at =
                       :retryAt,
                   termination_last_error = :lastError,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = :sessionId AND status = :terminating
               AND termination_claim_id = :claimId
            """, nativeQuery = true)
    int failTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("retryAt") java.time.LocalDateTime retryAt,
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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
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
