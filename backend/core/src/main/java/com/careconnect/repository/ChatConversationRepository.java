package com.careconnect.repository;

import com.careconnect.model.ChatConversation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface ChatConversationRepository extends JpaRepository<ChatConversation, Long> {

    Optional<ChatConversation> findByConversationIdAndIsActiveTrue(String conversationId);

    List<ChatConversation> findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(Long patientId);

    List<ChatConversation> findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(Long userId);

    @Query("SELECT c FROM ChatConversation c WHERE c.patientId = :patientId AND c.userId = :userId AND c.isActive = true ORDER BY c.updatedAt DESC")
    List<ChatConversation> findByPatientIdAndUserIdAndIsActiveTrueOrderByUpdatedAtDesc(
            @Param("patientId") Long patientId,
            @Param("userId") Long userId
    );

    @Query("SELECT COUNT(c) FROM ChatConversation c WHERE c.patientId = :patientId AND c.isActive = true")
    long countActiveConversationsByPatientId(@Param("patientId") Long patientId);

    // For cleanup service - find conversations older than specified time
    List<ChatConversation> findByCreatedAtBeforeAndIsActiveTrue(LocalDateTime cutoffTime);
}
