package com.careconnect.model.ai.ask;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/** Durable Ask AI conversation share receipt for provider medical-record review. */
@Entity
@Table(name = "ai_ask_conversation_share")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiAskConversationShare {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "patient_id", nullable = false, updatable = false)
    private Long patientId;

    @Column(name = "shared_by_user_id", nullable = false, updatable = false)
    private Long sharedByUserId;

    @Column(name = "session_id", updatable = false)
    private UUID sessionId;

    /** JSON array of recipient caregiver user ids. */
    @Column(name = "recipient_user_ids", nullable = false, updatable = false, columnDefinition = "TEXT")
    private String recipientUserIds;

    @Column(name = "message_count", nullable = false, updatable = false)
    private int messageCount;

    @Column(name = "transcript_json", nullable = false, updatable = false, columnDefinition = "TEXT")
    private String transcriptJson;

    @Column(name = "transcript_sha256", nullable = false, updatable = false, length = 64)
    private String transcriptSha256;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void onCreate() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
