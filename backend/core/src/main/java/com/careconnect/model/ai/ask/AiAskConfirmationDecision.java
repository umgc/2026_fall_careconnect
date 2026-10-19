package com.careconnect.model.ai.ask;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ai_ask_confirmation_decision")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AiAskConfirmationDecision {

    @Id
    @Column(name = "id", nullable = false)
    private UUID id;

    @Column(name = "session_id", nullable = false)
    private UUID sessionId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "caller_user_id", nullable = false)
    private Long callerUserId;

    @Column(name = "request_id")
    private UUID requestId;

    /**
     * APPROVE_ONCE | APPROVE_SESSION | DECLINE
     */
    @Column(name = "decision", nullable = false, length = 32)
    private String decision;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
}
