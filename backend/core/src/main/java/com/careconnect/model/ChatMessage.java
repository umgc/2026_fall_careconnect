package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "chat_messages")
public class ChatMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "conversation_id", nullable = false)
    private ChatConversation conversation;

    @Enumerated(EnumType.STRING)
    @Column(name = "message_type", nullable = false)
    private MessageType messageType;

    @Column(name = "content", columnDefinition = "TEXT", nullable = false)
    private String content;
    @Column(name = "tokens_used")
    private Integer tokensUsed;
    @Column(name = "processing_time_ms")
    private Long processingTimeMs;
    @Column(name = "temperature_used")
    private Double temperatureUsed;
    @Column(name = "context_included", columnDefinition = "TEXT")
    private String contextIncluded; // JSON string of what context was included
    @Column(name = "ai_model_used")
    private String aiModelUsed;
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    // Explicit getters and setters for compatibility
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public ChatConversation getConversation() {
        return conversation;
    }

    public void setConversation(ChatConversation conversation) {
        this.conversation = conversation;
    }

    public MessageType getMessageType() {
        return messageType;
    }

    public void setMessageType(MessageType messageType) {
        this.messageType = messageType;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Integer getTokensUsed() {
        return tokensUsed;
    }

    public void setTokensUsed(Integer tokensUsed) {
        this.tokensUsed = tokensUsed;
    }

    public Long getProcessingTimeMs() {
        return processingTimeMs;
    }

    public void setProcessingTimeMs(Long processingTimeMs) {
        this.processingTimeMs = processingTimeMs;
    }

    public Double getTemperatureUsed() {
        return temperatureUsed;
    }

    public void setTemperatureUsed(Double temperatureUsed) {
        this.temperatureUsed = temperatureUsed;
    }

    public String getContextIncluded() {
        return contextIncluded;
    }

    public void setContextIncluded(String contextIncluded) {
        this.contextIncluded = contextIncluded;
    }

    public String getAiModelUsed() {
        return aiModelUsed;
    }

    public void setAiModelUsed(String aiModelUsed) {
        this.aiModelUsed = aiModelUsed;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }

    public enum MessageType {
        USER("user"),
        ASSISTANT("assistant"),
        SYSTEM("system");

        private final String value;

        MessageType(String value) {
            this.value = value;
        }

        public String getValue() {
            return value;
        }
    }
}
