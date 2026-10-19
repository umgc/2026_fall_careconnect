package com.careconnect.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import lombok.Data;

/**
 * Configuration properties for ChatMemory settings
 * <p>
 * This allows fine-tuning of chat memory behavior through application properties
 */
@Configuration
@ConfigurationProperties(prefix = "careconnect.chat.memory")
@Data
public class ChatMemoryConfig {

    /**
     * Whether to use database persistence for chat memory (true) or in-memory only (false)
     * Default: true (recommended for production)
     */
    private boolean useDatabasePersistence = true;

    /**
     * Default maximum number of messages to keep in memory per conversation
     * Default: 20
     */
    private int defaultMaxMessages = 20;

    /**
     * Maximum number of messages for premium users
     * Default: 50
     */
    private int premiumMaxMessages = 50;

    /**
     * Whether to automatically clean up old conversations
     * Default: true
     */
    private boolean autoCleanup = true;

    /**
     * Number of days after which inactive conversations are cleaned up
     * Default: 30 days
     */
    private int cleanupAfterDays = 30;

    /**
     * Whether to compress old messages to save storage
     * Default: false
     */
    private boolean compressOldMessages = false;

    /**
     * Whether to enable conversation summarization for long chats
     * Default: true
     */
    private boolean enableSummarization = true;

    /**
     * Number of messages after which to create a summary
     * Default: 100
     */
    private int summarizationThreshold = 100;
}