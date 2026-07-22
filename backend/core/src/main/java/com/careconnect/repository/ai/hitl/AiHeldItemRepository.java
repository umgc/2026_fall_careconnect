package com.careconnect.repository.ai.hitl;

import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.model.ai.hitl.AiHeldItemStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface AiHeldItemRepository extends JpaRepository<AiHeldItem, UUID> {

    List<AiHeldItem> findByStatusOrderByCreatedAtAsc(AiHeldItemStatus status);

    List<AiHeldItem> findByPatientIdAndStatusOrderByCreatedAtAsc(
            Long patientId, AiHeldItemStatus status);

    /**
     * Conditional status transition for release/reject races.
     *
     * @return 1 when the row was still {@code expectedStatus}; 0 if another writer won
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AiHeldItem h
            SET h.status = :newStatus,
                h.deliveryStatus = :deliveryStatus,
                h.finalAnswer = :finalAnswer,
                h.reviewerUserId = :reviewerUserId,
                h.reviewedAt = :reviewedAt,
                h.reviewNotes = :reviewNotes,
                h.updatedAt = :updatedAt
            WHERE h.id = :id AND h.status = :expectedStatus
            """)
    int updateOutcomeIfStatus(
            @Param("id") UUID id,
            @Param("expectedStatus") AiHeldItemStatus expectedStatus,
            @Param("newStatus") AiHeldItemStatus newStatus,
            @Param("deliveryStatus") String deliveryStatus,
            @Param("finalAnswer") String finalAnswer,
            @Param("reviewerUserId") Long reviewerUserId,
            @Param("reviewedAt") Instant reviewedAt,
            @Param("reviewNotes") String reviewNotes,
            @Param("updatedAt") Instant updatedAt);

    /**
     * Expire a pending hold only if it is still pending and past {@code expiresAt}.
     *
     * @return 1 when this caller won the expire transition; 0 if release/reject won
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AiHeldItem h
            SET h.status = com.careconnect.model.ai.hitl.AiHeldItemStatus.EXPIRED,
                h.deliveryStatus = 'WITHHELD_PERMANENTLY',
                h.updatedAt = :now
            WHERE h.id = :id
              AND h.status = com.careconnect.model.ai.hitl.AiHeldItemStatus.PENDING_REVIEW
              AND h.expiresAt IS NOT NULL
              AND h.expiresAt < :now
            """)
    int expireIfPending(@Param("id") UUID id, @Param("now") Instant now);
}
