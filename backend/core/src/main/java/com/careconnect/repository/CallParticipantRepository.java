package com.careconnect.repository;

import com.careconnect.model.CallParticipant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

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

    long countByCallSessionIdAndStatus(Long callSessionId, String status);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallParticipant p
               SET p.status = :joined, p.joinedAt = COALESCE(p.joinedAt, CURRENT_TIMESTAMP),
                   p.leftAt = NULL, p.updatedAt = CURRENT_TIMESTAMP
             WHERE p.callSessionId = :sessionId AND p.userId = :userId
               AND p.status IN (:invited, :joined)
            """)
    int markJoinedIfInvited(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("invited") String invited,
            @Param("joined") String joined);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallParticipant p SET p.status = :left, p.leftAt = CURRENT_TIMESTAMP,
                   p.updatedAt = CURRENT_TIMESTAMP
             WHERE p.callSessionId = :sessionId AND p.userId = :userId
               AND p.status = :joined
            """)
    int markLeftIfJoined(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("joined") String joined,
            @Param("left") String left);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallParticipant p SET p.status = :expired, p.leftAt = CURRENT_TIMESTAMP,
                   p.updatedAt = CURRENT_TIMESTAMP
             WHERE p.callSessionId = :sessionId AND p.status = :joined
            """)
    int expireJoinedParticipants(
            @Param("sessionId") Long sessionId,
            @Param("joined") String joined,
            @Param("expired") String expired);

    @Modifying
    @Transactional
    @Query("""
            UPDATE CallParticipant p SET p.status = :declined, p.leftAt = CURRENT_TIMESTAMP,
                   p.updatedAt = CURRENT_TIMESTAMP
             WHERE p.callSessionId = :sessionId AND p.userId = :userId
               AND p.status = :invited
            """)
    int declineIfInvited(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("invited") String invited,
            @Param("declined") String declined);
}
