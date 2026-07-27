package com.careconnect.repository.ai.ask;

import com.careconnect.model.ai.ask.AiAskConversationShare;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AiAskConversationShareRepository extends JpaRepository<AiAskConversationShare, UUID> {

    Optional<AiAskConversationShare> findFirstByPatientIdAndSharedByUserIdAndTranscriptSha256OrderByCreatedAtDesc(
            Long patientId, Long sharedByUserId, String transcriptSha256);

    List<AiAskConversationShare> findByPatientIdOrderByCreatedAtDesc(Long patientId);

    /**
     * Lists shares visible to the caller. When {@code elevated} is true (admin), all patient
     * shares are returned. Otherwise the caller must be the sharer or a normalized recipient.
     */
    @Query("""
            SELECT DISTINCT s FROM AiAskConversationShare s
            LEFT JOIN AiAskShareRecipient r ON r.shareId = s.id
            WHERE s.patientId = :patientId
              AND (
                   :elevated = TRUE
                   OR s.sharedByUserId = :callerId
                   OR r.userId = :callerId
              )
            ORDER BY s.createdAt DESC
            """)
    List<AiAskConversationShare> findVisibleForCaller(
            @Param("patientId") Long patientId,
            @Param("callerId") Long callerId,
            @Param("elevated") boolean elevated);
}
