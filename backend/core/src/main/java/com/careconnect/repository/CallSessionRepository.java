package com.careconnect.repository;

import com.careconnect.model.CallSession;
import jakarta.persistence.LockModeType;
import java.util.Optional;
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
               SET s.chimeMeetingId = :meetingId
             WHERE s.callId = :callId
               AND (s.chimeMeetingId IS NULL OR s.chimeMeetingId = :meetingId)
            """)
    int persistMeetingIdIfAbsent(
            @Param("callId") String callId, @Param("meetingId") String meetingId);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallSession s SET s.chimeMeetingId = NULL
             WHERE s.callId = :callId AND s.chimeMeetingId = :meetingId
            """)
    int clearMeetingId(
            @Param("callId") String callId, @Param("meetingId") String meetingId);

    @Modifying
    @Query("""
            UPDATE CallSession s
               SET s.status = :active, s.chimeMeetingId = COALESCE(s.chimeMeetingId, :meetingId)
             WHERE s.id = :sessionId AND s.status IN (:created, :active)
            """)
    int activateIfJoinable(
            @Param("sessionId") Long sessionId,
            @Param("meetingId") String meetingId,
            @Param("created") String created,
            @Param("active") String active);

    @Modifying
    @Query("""
            UPDATE CallSession s SET s.status = :terminating
             WHERE s.id = :sessionId AND s.status IN (:created, :active)
            """)
    int beginTermination(
            @Param("sessionId") Long sessionId,
            @Param("created") String created,
            @Param("active") String active,
            @Param("terminating") String terminating);

    @Modifying
    @Query("""
            UPDATE CallSession s SET s.status = :ended, s.endedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status = :terminating
            """)
    int completeTermination(
            @Param("sessionId") Long sessionId,
            @Param("terminating") String terminating,
            @Param("ended") String ended);

    @Modifying
    @Query("""
            UPDATE CallSession s SET s.status = :cancelled, s.endedAt = CURRENT_TIMESTAMP
             WHERE s.id = :sessionId AND s.status = :created
            """)
    int cancelIfNotActive(
            @Param("sessionId") Long sessionId,
            @Param("created") String created,
            @Param("cancelled") String cancelled);
}
