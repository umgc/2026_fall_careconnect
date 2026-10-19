package com.careconnect.service;

import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.UserMessage;
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.memory.ChatMemory;
import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage.MessageType;
import com.careconnect.repository.ChatMessageRepository;
import lombok.extern.slf4j.Slf4j;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

/**
 * Session-based ChatMemory implementation with database persistence
 * <p>
 * This implementation provides:
 * - Database persistence for chat history
 * - Session timeout (15 minutes of inactivity)
 * - Automatic cleanup after timeout
 * - Limited context window (10-20 messages per session)
 * <p>
 * Chat history persists within the same session but resets after 15 minutes of inactivity.
 */
@Slf4j
public class SessionBasedChatMemory implements ChatMemory {

    private final ChatMessageRepository chatMessageRepository;
    private final ChatConversation conversation;
    private final String sessionId;
    private final int maxMessages;
    private final long sessionTimeoutMinutes;

    private Instant lastActivity;

    public SessionBasedChatMemory(ChatMessageRepository chatMessageRepository,
                                  ChatConversation conversation,
                                  int maxMessages,
                                  long sessionTimeoutMinutes) {
        this.chatMessageRepository = chatMessageRepository;
        this.conversation = conversation;
        this.sessionId = conversation.getConversationId();
        this.maxMessages = maxMessages;
        this.sessionTimeoutMinutes = sessionTimeoutMinutes;
        this.lastActivity = Instant.now();

        log.debug("Created session-based ChatMemory for conversation {} with {} max messages and {} minute timeout",
                sessionId, maxMessages, sessionTimeoutMinutes);
    }

    @Override
    public Object id() {
        return sessionId;
    }

    @Override
    public void add(ChatMessage message) {
        updateActivity();

        // Check if session has expired
        if (isSessionExpired()) {
            log.debug("Session {} expired, clearing old messages", sessionId);
            clearExpiredSession();
        }

        // Convert LangChain4j ChatMessage to database ChatMessage and save
        com.careconnect.model.ChatMessage dbMessage = convertToDbMessage(message);
        chatMessageRepository.save(dbMessage);

        // Clean up old messages if we exceed the limit
        cleanupOldMessages();

        log.debug("Added message to session {}, total messages: {}", sessionId, getMessageCount());
    }

    @Override
    public List<ChatMessage> messages() {
        updateActivity();

        // Check if session has expired
        if (isSessionExpired()) {
            log.debug("Session {} expired during message retrieval, clearing old messages", sessionId);
            clearExpiredSession();
            return new ArrayList<>(); // Return empty list for expired session
        }

        // Get recent messages from database
        List<com.careconnect.model.ChatMessage> dbMessages = chatMessageRepository
                .findTopNByConversationOrderByCreatedAtAsc(conversation, maxMessages);

        // Convert to LangChain4j ChatMessage objects
        List<ChatMessage> langchainMessages = new ArrayList<>();
        for (com.careconnect.model.ChatMessage dbMsg : dbMessages) {
            ChatMessage langchainMsg = convertToLangchainMessage(dbMsg);
            if (langchainMsg != null) {
                langchainMessages.add(langchainMsg);
            }
        }

        return langchainMessages;
    }

    @Override
    public void clear() {
        log.info("Clearing session {} memory", sessionId);
        List<com.careconnect.model.ChatMessage> messages = chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation);
        chatMessageRepository.deleteAll(messages);
        updateActivity();
    }

    /**
     * Check if the current session has expired
     */
    private boolean isSessionExpired() {
        return ChronoUnit.MINUTES.between(lastActivity, Instant.now()) > sessionTimeoutMinutes;
    }

    /**
     * Update the last activity timestamp
     */
    private void updateActivity() {
        this.lastActivity = Instant.now();
    }

    /**
     * Clear expired session messages
     */
    private void clearExpiredSession() {
        log.debug("Clearing expired session for {}", sessionId);
        List<com.careconnect.model.ChatMessage> messages = chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation);
        chatMessageRepository.deleteAll(messages);
        updateActivity();
    }

    /**
     * Get current message count
     */
    private int getMessageCount() {
        return chatMessageRepository.countByConversation(conversation);
    }

    /**
     * Convert LangChain4j ChatMessage to database ChatMessage
     */
    private com.careconnect.model.ChatMessage convertToDbMessage(ChatMessage message) {
        MessageType messageType;
        String content;

        if (message instanceof SystemMessage) {
            messageType = MessageType.SYSTEM;
            content = ((SystemMessage) message).text();
        } else if (message instanceof UserMessage) {
            messageType = MessageType.USER;
            content = ((UserMessage) message).singleText();
        } else if (message instanceof AiMessage) {
            messageType = MessageType.ASSISTANT;
            content = ((AiMessage) message).text();
        } else {
            messageType = MessageType.USER; // fallback
            content = message.toString();
        }

        return com.careconnect.model.ChatMessage.builder()
                .conversation(conversation)
                .messageType(messageType)
                .content(content)
                .build();
    }

    /**
     * Convert database ChatMessage to LangChain4j ChatMessage
     */
    private ChatMessage convertToLangchainMessage(com.careconnect.model.ChatMessage dbMessage) {
        String content = dbMessage.getContent();

        return switch (dbMessage.getMessageType()) {
            case SYSTEM -> SystemMessage.from(content);
            case USER -> UserMessage.from(content);
            case ASSISTANT -> AiMessage.from(content);
            default -> {
                log.warn("Unknown message type: {}", dbMessage.getMessageType());
                yield null;
            }
        };
    }

    /**
     * Clean up old messages to maintain the maxMessages limit
     */
    private void cleanupOldMessages() {
        try {
            List<com.careconnect.model.ChatMessage> allMessages = chatMessageRepository
                    .findByConversationOrderByCreatedAtAsc(conversation);

            if (allMessages.size() > maxMessages) {
                int messagesToDeleteCount = allMessages.size() - maxMessages;
                List<com.careconnect.model.ChatMessage> messagesToDelete = allMessages.subList(0, messagesToDeleteCount);

                chatMessageRepository.deleteAll(messagesToDelete);

                log.debug("Cleaned up {} old messages from conversation {}",
                        messagesToDelete.size(), conversation.getConversationId());
            }
        } catch (Exception e) {
            log.error("Failed to cleanup old messages", e);
        }
    }

    /**
     * Get session statistics for monitoring
     */
    public SessionStats getSessionStats() {
        return SessionStats.builder()
                .sessionId(sessionId)
                .messageCount(getMessageCount())
                .lastActivity(lastActivity)
                .isExpired(isSessionExpired())
                .build();
    }

    /**
     * Session statistics for monitoring and debugging
     */
    @lombok.Builder
    @lombok.Data
    public static class SessionStats {
        private String sessionId;
        private int messageCount;
        private Instant lastActivity;
        private boolean isExpired;
    }
}
