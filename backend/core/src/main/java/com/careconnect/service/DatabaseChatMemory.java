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

import java.util.ArrayList;
import java.util.List;

/**
 * Database-persistent ChatMemory implementation for LangChain4j
 * <p>
 * This implementation stores chat history in the database while providing
 * LangChain4j ChatMemory interface for seamless integration.
 * <p>
 * Note: This class is not a Spring @Service because it requires manual instantiation
 * with specific ChatConversation objects via ChatMemoryFactory.
 */
@Slf4j
public class DatabaseChatMemory implements ChatMemory {

    private final ChatMessageRepository chatMessageRepository;
    private final ChatConversation conversation;
    private final int maxMessages;

    public DatabaseChatMemory(ChatMessageRepository chatMessageRepository,
                              ChatConversation conversation,
                              int maxMessages) {
        this.chatMessageRepository = chatMessageRepository;
        this.conversation = conversation;
        this.maxMessages = maxMessages;
    }

    @Override
    public Object id() {
        return conversation.getConversationId();
    }

    @Override
    public void add(ChatMessage message) {
        try {
            // Convert LangChain4j ChatMessage to database ChatMessage
            com.careconnect.model.ChatMessage dbMessage = convertToDbMessage(message);
            chatMessageRepository.save(dbMessage);

            // Clean up old messages if we exceed the limit
            cleanupOldMessages();

            log.debug("Added message to conversation {}: {}",
                    conversation.getConversationId(), message.type());
        } catch (Exception e) {
            log.error("Failed to add message to database", e);
            throw new RuntimeException("Failed to persist chat message", e);
        }
    }

    @Override
    public List<ChatMessage> messages() {
        try {
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

            log.debug("Retrieved {} messages for conversation {}",
                    langchainMessages.size(), conversation.getConversationId());

            return langchainMessages;
        } catch (Exception e) {
            log.error("Failed to retrieve messages from database", e);
            return new ArrayList<>();
        }
    }

    @Override
    public void clear() {
        try {
            List<com.careconnect.model.ChatMessage> messages = chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation);
            chatMessageRepository.deleteAll(messages);
            log.info("Cleared all messages for conversation {}",
                    conversation.getConversationId());
        } catch (Exception e) {
            log.error("Failed to clear messages from database", e);
            throw new RuntimeException("Failed to clear chat history", e);
        }
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
}
