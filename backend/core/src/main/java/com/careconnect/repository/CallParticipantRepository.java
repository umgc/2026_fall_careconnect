package com.careconnect.repository;

import com.careconnect.model.CallParticipant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CallParticipantRepository extends JpaRepository<CallParticipant, Long> {
    Optional<CallParticipant> findByCallSessionIdAndUserId(Long callSessionId, Long userId);
    List<CallParticipant> findByCallSessionId(Long callSessionId);
    List<CallParticipant> findByCallSessionIdAndStatus(Long callSessionId, String status);

    @Modifying
    @Query(value = """
            INSERT INTO call_participants
              (call_session_id, user_id, invited_by_user_id, status, created_at, updated_at)
            VALUES
              (:sessionId, :userId, :invitedByUserId, :status, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (call_session_id, user_id) DO NOTHING
            """, nativeQuery = true)
    int insertIfAbsent(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("invitedByUserId") Long invitedByUserId,
            @Param("status") String status);
}
