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
}
