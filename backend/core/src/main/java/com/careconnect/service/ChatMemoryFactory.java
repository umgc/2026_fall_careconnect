package com.careconnect.service;

import dev.langchain4j.memory.ChatMemory;
import dev.langchain4j.memory.chat.MessageWindowChatMemory;
import com.careconnect.config.ChatMemoryConfig;
import com.careconnect.model.ChatConversation;
import com.careconnect.model.UserAIConfig;
import com.careconnect.repository.ChatMessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Factory for creating ChatMemory instances with different strategies
 * <p>
 * Provides session-based (recommended for healthcare), in-memory, and database-persistent
 * chat memory options based on configuration and requirements.
 * <p>
 * Healthcare Safety: Session-based memory is recommended to prevent cross-conversation
 * connections and maintain clear boundaries between interactions.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ChatMemoryFactory {

    private final ChatMessageRepository chatMessageRepository;
    private final ChatMemoryConfig chatMemoryConfig;

    /**
     * Create a ChatMemory instance for the given conversation and configuration
     *
     * @param conversation The chat conversation
     * @param aiConfig     User AI configuration (for memory limits)
     * @param useDatabase  Whether to use database persistence (true) or in-memory (false)
     * @return ChatMemory instance
     */
    public ChatMemory createChatMemory(ChatConversation conversation,
                                       UserAIConfig aiConfig,
                                       boolean useDatabase) {

        int maxMessages = getMaxMessages(aiConfig);

        if (useDatabase) {
            log.debug("Creating database-persistent ChatMemory for conversation {} with {} max messages",
                    conversation.getConversationId(), maxMessages);
            return new DatabaseChatMemory(chatMessageRepository, conversation, maxMessages);
        } else {
            log.debug("Creating in-memory ChatMemory for conversation {} with {} max messages",
                    conversation.getConversationId(), maxMessages);
            return MessageWindowChatMemory.withMaxMessages(maxMessages);
        }
    }

    /**
     * Create a database-persistent ChatMemory (recommended for production)
     */
    public ChatMemory createDatabaseChatMemory(ChatConversation conversation, UserAIConfig aiConfig) {
        return createChatMemory(conversation, aiConfig, true);
    }

    /**
     * Create an in-memory ChatMemory (useful for testing or temporary conversations)
     */
    public ChatMemory createInMemoryChatMemory(ChatConversation conversation, UserAIConfig aiConfig) {
        return createChatMemory(conversation, aiConfig, false);
    }

    /**
     * Create a session-based ChatMemory with database persistence and timeout
     * <p>
     * This provides the best user experience:
     * - Database persistence for chat history
     * - Session timeout (15 minutes of inactivity)
     * - Automatic cleanup after timeout
     * - Limited context window (10-20 messages)
     */
    public ChatMemory createSessionBasedChatMemory(ChatConversation conversation, UserAIConfig aiConfig) {
        int maxMessages = getMaxMessages(aiConfig);
        // Limit to healthcare-safe message count
        int safeMaxMessages = Math.min(maxMessages, 15);

        log.debug("Creating session-based ChatMemory for conversation {} with {} max messages and 15-minute timeout",
                conversation.getConversationId(), safeMaxMessages);

        return new SessionBasedChatMemory(chatMessageRepository, conversation, safeMaxMessages, 15); // 15-minute timeout
    }

    /**
     * Create a session-based ChatMemory with custom timeout
     */
    public ChatMemory createSessionBasedChatMemory(ChatConversation conversation, UserAIConfig aiConfig, long timeoutMinutes) {
        int maxMessages = getMaxMessages(aiConfig);
        int safeMaxMessages = Math.min(maxMessages, 15);

        log.debug("Creating session-based ChatMemory for conversation {} with {} max messages and {} minute timeout",
                conversation.getConversationId(), safeMaxMessages, timeoutMinutes);

        return new SessionBasedChatMemory(chatMessageRepository, conversation, safeMaxMessages, timeoutMinutes);
    }

    /**
     * Get the maximum number of messages from AI config or use configured defaults
     */
    private int getMaxMessages(UserAIConfig aiConfig) {
        if (aiConfig != null && aiConfig.getConversationHistoryLimit() != null) {
            return aiConfig.getConversationHistoryLimit();
        }
        // TODO: Check if user has premium subscription
        // For now, use default limit
        return chatMemoryConfig.getDefaultMaxMessages();
    }
}
