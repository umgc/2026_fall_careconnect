package com.careconnect.repository;

import com.careconnect.model.InviteToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface InviteTokenRepository extends JpaRepository<InviteToken, Long> {

    /**
     * Primary lookup for the redeem/preview flow: find by the non-secret prefix,
     * then verify the hash in the service layer.
     */
    Optional<InviteToken> findByTokenLookup(String tokenLookup);

    /** All tokens ever issued for a link, newest first (history / audit views). */
    List<InviteToken> findByLinkIdOrderByCreatedAtDesc(Long linkId);

    /**
     * Guard for the one-active-token-per-link invariant. A token counts as
     * "active" when it is PENDING and not yet past its TTL.
     */
    @Query("""
        SELECT CASE WHEN COUNT(t) > 0 THEN true ELSE false END
        FROM InviteToken t
        WHERE t.linkId = :linkId
          AND t.status = com.careconnect.model.InviteToken.Status.PENDING
          AND t.expiresAt > :now
        """)
    boolean existsActivePendingToken(@Param("linkId") Long linkId,
                                     @Param("now") LocalDateTime now);

    @Query("""
        SELECT t FROM InviteToken t
        WHERE t.linkId = :linkId
          AND t.status = com.careconnect.model.InviteToken.Status.PENDING
          AND t.expiresAt > :now
        """)
    Optional<InviteToken> findActivePendingToken(@Param("linkId") Long linkId,
                                                 @Param("now") LocalDateTime now);

    /**
     * Bulk-expire overdue PENDING tokens. Used by the scheduled sweep. Returns
     * the number of rows updated so the caller can log/metric it.
     */
    @Modifying
    @Query("""
        UPDATE InviteToken t
        SET t.status = com.careconnect.model.InviteToken.Status.EXPIRED,
            t.updatedAt = :now
        WHERE t.status = com.careconnect.model.InviteToken.Status.PENDING
          AND t.expiresAt <= :now
        """)
    int expireOverdueTokens(@Param("now") LocalDateTime now);

    /**
     * Revoke every PENDING token for a link in one statement (e.g. when the
     * underlying link is revoked/suspended).
     */
    @Modifying
    @Query("""
        UPDATE InviteToken t
        SET t.status = com.careconnect.model.InviteToken.Status.REVOKED,
            t.revokedByUserId = :actorId,
            t.revokedAt = :now,
            t.revokeReason = :reason,
            t.updatedAt = :now
        WHERE t.linkId = :linkId
          AND t.status = com.careconnect.model.InviteToken.Status.PENDING
        """)
    int revokeAllPendingForLink(@Param("linkId") Long linkId,
                                @Param("actorId") Long actorId,
                                @Param("reason") String reason,
                                @Param("now") LocalDateTime now);
}
