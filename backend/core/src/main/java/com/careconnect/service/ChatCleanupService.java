package com.careconnect.service;

import com.careconnect.config.ChatMemoryConfig;
import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.repository.ChatMessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Service for automatic cleanup of chat conversations and messages
 * <p>
 * Healthcare Compliance: Chat logs are retained for 30 days by default
 * to support patient care continuity while balancing privacy requirements.
 * <p>
 * Configurable retention period supports both privacy and clinical needs.
 * Only metadata and anonymized analytics are retained long-term.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ChatCleanupService {

    private final ChatConversationRepository chatConversationRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final ChatAnalyticsService chatAnalyticsService;
    private final ChatMemoryConfig chatMemoryConfig;

    /**
     * Scheduled cleanup task that runs every hour
     * Deletes conversations and messages older than configured retention period
     */
    @Scheduled(fixedRate = 3600000) // Run every hour (3600000 ms)
    @Transactional
    public void cleanupOldChats() {
        try {
            if (!chatMemoryConfig.isAutoCleanup()) {
                log.debug("Auto cleanup is disabled, skipping chat cleanup");
                return;
            }

            LocalDateTime cutoffTime = LocalDateTime.now().minusDays(chatMemoryConfig.getCleanupAfterDays());

            log.info("Starting chat cleanup - deleting conversations older than {} days", chatMemoryConfig.getCleanupAfterDays());

            // Find conversations older than configured retention period
            List<ChatConversation> oldConversations = chatConversationRepository
                    .findByCreatedAtBeforeAndIsActiveTrue(cutoffTime);

            int deletedConversations = 0;
            int deletedMessages = 0;

            for (ChatConversation conversation : oldConversations) {
                // Get messages before deletion for analytics
                List<ChatMessage> messages = chatMessageRepository
                        .findByConversationOrderByCreatedAtAsc(conversation);

                // Collect anonymized analytics before deletion
                if (!messages.isEmpty()) {
                    chatAnalyticsService.collectAnalytics(conversation, messages);
                }

                // Delete all messages in the conversation
                if (!messages.isEmpty()) {
                    chatMessageRepository.deleteAll(messages);
                    deletedMessages += messages.size();
                }

                // Mark conversation as inactive (soft delete)
                conversation.setIsActive(false);
                chatConversationRepository.save(conversation);
                deletedConversations++;
            }

            if (deletedConversations > 0) {
                log.info("Chat cleanup completed: {} conversations and {} messages deleted",
                        deletedConversations, deletedMessages);
            } else {
                log.debug("Chat cleanup completed: no old conversations found");
            }

        } catch (Exception e) {
            log.error("Error during chat cleanup", e);
        }
    }

    /**
     * Manual cleanup for a specific conversation (for immediate deletion)
     */
    @Transactional
    public void deleteConversationImmediately(String conversationId) {
        try {
            ChatConversation conversation = chatConversationRepository
                    .findByConversationIdAndIsActiveTrue(conversationId)
                    .orElse(null);

            if (conversation != null) {
                // Delete all messages
                List<ChatMessage> messages = chatMessageRepository
                        .findByConversationOrderByCreatedAtAsc(conversation);

                if (!messages.isEmpty()) {
                    chatMessageRepository.deleteAll(messages);
                }

                // Mark conversation as inactive
                conversation.setIsActive(false);
                chatConversationRepository.save(conversation);

                log.info("Immediately deleted conversation: {} with {} messages",
                        conversationId, messages.size());
            }
        } catch (Exception e) {
            log.error("Error deleting conversation immediately: {}", conversationId, e);
            throw new RuntimeException("Failed to delete conversation", e);
        }
    }

    /**
     * Get retention policy information for user transparency
     */
    public String getRetentionPolicyInfo() {
        if (chatMemoryConfig.isAutoCleanup()) {
            return String.format(
                    "Your chat conversations are automatically deleted after %d days to balance patient care continuity with privacy protection. " +
                            "You can delete conversations immediately anytime. Only anonymized usage statistics are retained long-term.",
                    chatMemoryConfig.getCleanupAfterDays()
            );
        } else {
            return "Automatic chat deletion is currently disabled. You can manually delete conversations anytime. " +
                    "Only anonymized usage statistics are retained long-term.";
        }
    }
}
