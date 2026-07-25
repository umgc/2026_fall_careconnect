package com.careconnect.repository;

import com.careconnect.model.CallParticipant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface CallParticipantRepository extends JpaRepository<CallParticipant, Long> {
    Optional<CallParticipant> findByCallSessionIdAndUserId(Long callSessionId, Long userId);
    List<CallParticipant> findByCallSessionId(Long callSessionId);
    List<CallParticipant> findByCallSessionIdAndStatus(Long callSessionId, String status);

    /** Resolves opaque Chime externalUserId → durable participant (user id). */
    Optional<CallParticipant> findFirstByChimeExternalUserId(String chimeExternalUserId);

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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE CallParticipant p
               SET p.status = :invited, p.invitedByUserId = :invitedByUserId,
                   p.joinedAt = NULL, p.leftAt = NULL, p.updatedAt = CURRENT_TIMESTAMP
             WHERE p.callSessionId = :sessionId AND p.userId = :userId
               AND p.status IN (:left, :declined)
            """)
    int reinviteIfInactive(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("invitedByUserId") Long invitedByUserId,
            @Param("invited") String invited,
            @Param("left") String left,
            @Param("declined") String declined);

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

    /**
     * Reverts a ghost JOINED row back to INVITED when Chime attendee creation never persisted
     * and no concurrent claim is in flight.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("""
            UPDATE CallParticipant p
               SET p.status = :invited, p.joinedAt = NULL, p.leftAt = NULL,
                   p.updatedAt = CURRENT_TIMESTAMP
             WHERE p.callSessionId = :sessionId AND p.userId = :userId
               AND p.status = :joined
               AND p.chimeAttendeeId IS NULL
               AND p.attendeeClaimToken IS NULL
            """)
    int revertJoinedToInvitedWithoutAttendee(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("joined") String joined,
            @Param("invited") String invited);

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

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            UPDATE call_participants
               SET attendee_claim_token = :claimToken,
                   attendee_claimed_until = :claimedUntil,
                   chime_external_user_id = COALESCE(chime_external_user_id, :externalUserId),
                   updated_at = CURRENT_TIMESTAMP
             WHERE call_session_id = :sessionId
               AND user_id = :userId
               AND chime_attendee_id IS NULL
               AND (attendee_claim_token IS NULL
                    OR attendee_claimed_until IS NULL
                    OR attendee_claimed_until < :now)
            """, nativeQuery = true)
    int claimAttendeeCreation(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("claimToken") UUID claimToken,
            @Param("claimedUntil") LocalDateTime claimedUntil,
            @Param("externalUserId") String externalUserId,
            @Param("now") LocalDateTime now);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            UPDATE call_participants
               SET chime_external_user_id = :externalUserId,
                   chime_attendee_id = :attendeeId,
                   chime_join_token = :joinToken,
                   attendee_claim_token = NULL,
                   attendee_claimed_until = NULL,
                   updated_at = CURRENT_TIMESTAMP
             WHERE call_session_id = :sessionId
               AND user_id = :userId
               AND attendee_claim_token = :claimToken
            """, nativeQuery = true)
    int finalizeAttendeeCreation(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("claimToken") UUID claimToken,
            @Param("externalUserId") String externalUserId,
            @Param("attendeeId") String attendeeId,
            @Param("joinToken") String joinToken);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            UPDATE call_participants
               SET attendee_claim_token = NULL,
                   attendee_claimed_until = NULL,
                   updated_at = CURRENT_TIMESTAMP
             WHERE call_session_id = :sessionId
               AND user_id = :userId
               AND attendee_claim_token = :claimToken
               AND chime_attendee_id IS NULL
            """, nativeQuery = true)
    int releaseAttendeeClaim(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("claimToken") UUID claimToken);

    /**
     * Ensures opaque Chime {@code externalUserId} is stored for EventBridge / roster resolve when
     * an attendee row already has credentials from an earlier join.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            UPDATE call_participants
               SET chime_external_user_id = :externalUserId,
                   updated_at = CURRENT_TIMESTAMP
             WHERE call_session_id = :sessionId
               AND user_id = :userId
               AND (chime_external_user_id IS NULL OR BTRIM(chime_external_user_id) = '')
            """, nativeQuery = true)
    int backfillChimeExternalUserIdIfBlank(
            @Param("sessionId") Long sessionId,
            @Param("userId") Long userId,
            @Param("externalUserId") String externalUserId);
}
