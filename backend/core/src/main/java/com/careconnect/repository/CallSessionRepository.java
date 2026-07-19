package com.careconnect.repository;

import com.careconnect.model.CallSession;
import jakarta.persistence.LockModeType;
import java.time.LocalDateTime;
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
    @Query("""
            UPDATE CallSession s
               SET s.status = :terminating,
                   s.terminationClaimId = :claimId,
                   s.terminationClaimedByUserId = :claimedByUserId,
                   s.terminationLeaseUntil = :leaseUntil,
                   s.terminationAttemptCount = s.terminationAttemptCount + 1,
                   s.terminationNextRetryAt = NULL,
                   s.terminationLastError = NULL,
                   s.terminationNotifyUserIds = :notifyUserIds,
                   s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status IN (:created, :active)
            """)
    int beginTermination(
            @Param("sessionId") Long sessionId,
            @Param("created") String created,
            @Param("active") String active,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("claimedByUserId") Long claimedByUserId,
            @Param("leaseUntil") LocalDateTime leaseUntil,
            @Param("notifyUserIds") String notifyUserIds);

    @Modifying
    @Query("""
            UPDATE CallSession s
               SET s.terminationClaimId = :claimId,
                   s.terminationClaimedByUserId = :claimedByUserId,
                   s.terminationLeaseUntil = :leaseUntil,
                   s.terminationAttemptCount = s.terminationAttemptCount + 1,
                   s.terminationNextRetryAt = NULL,
                   s.terminationLastError = NULL,
                   s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId
               AND s.status = :terminating
               AND (s.terminationLeaseUntil IS NULL OR s.terminationLeaseUntil <= :now)
               AND (s.terminationNextRetryAt IS NULL OR s.terminationNextRetryAt <= :now)
            """)
    int reclaimTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("claimedByUserId") Long claimedByUserId,
            @Param("now") LocalDateTime now,
            @Param("leaseUntil") LocalDateTime leaseUntil);

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
    @Query("""
            UPDATE CallSession s
               SET s.terminationLeaseUntil = NULL,
                   s.terminationNextRetryAt = :nextRetryAt,
                   s.terminationLastError = :lastError,
                   s.updatedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status = :terminating
               AND s.terminationClaimId = :claimId
            """)
    int failTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("claimId") UUID claimId,
            @Param("nextRetryAt") LocalDateTime nextRetryAt,
            @Param("lastError") String lastError);

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
