package com.careconnect.service;

import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.repository.ChatMessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * Stores temporary Alexa authorization codes mapped to JWT tokens.
 * Codes expire automatically after a short period (e.g., 120 seconds).
 */
@Service
public class AlexaCodeStoreService {

    private static final long EXPIRATION_SECONDS = 120; // ⏱️ Temp codes last 1 minute
    private final Map<String, Entry> codeStore = new ConcurrentHashMap<>();
    private final Map<String, String> refreshTokenStore = new ConcurrentHashMap<>();

    /**
     * Generate a new temporary code tied to a user's JWT.
     */
    public String generateCode(String jwtToken) {
        String code = UUID.randomUUID().toString();
        codeStore.put(code, new Entry(jwtToken, Instant.now().plusSeconds(EXPIRATION_SECONDS)));
        return code;
    }

    /**
     * Exchange a code for the associated JWT.
     * Once consumed, the code is invalidated (one-time use).
     */
    public String consumeCode(String code) {
        Entry entry = codeStore.remove(code);
        if (entry == null) {
            return null; // invalid or already used
        }
        if (Instant.now().isAfter(entry.expiration)) {
            return null; // expired
        }
        return entry.jwt;
    }

    public void saveRefreshToken(String refreshToken, String jwtToken) {
        refreshTokenStore.put(refreshToken, jwtToken);
    }

    public String findJwtByRefreshToken(String refreshToken) {
        return refreshTokenStore.get(refreshToken);
    }

    /**
     * Background cleanup (optional optimization).
     * Could be scheduled if you expect many tokens.
     */
    public void cleanupExpiredCodes() {
        Instant now = Instant.now();
        codeStore.entrySet().removeIf(e -> now.isAfter(e.getValue().expiration));
    }

    private static class Entry {
        final String jwt;
        final Instant expiration;

        Entry(String jwt, Instant expiration) {
            this.jwt = jwt;
            this.expiration = expiration;
        }
    }

    /**
     * Service for collecting anonymized analytics from chat conversations
     * <p>
     * Privacy Policy: Only aggregated, anonymized statistics are retained long-term.
     * No individual user data, conversation content, or personal information is stored.
     * <p>
     * Analytics collected:
     * - Usage patterns (time of day, session length)
     * - Topic categories (medication questions, symptom tracking, etc.)
     * - AI response effectiveness
     * - System performance metrics
     */
    @Service
    @RequiredArgsConstructor
    @Slf4j
    public static class ChatAnalyticsService {

        private final ChatConversationRepository chatConversationRepository;
        private final ChatMessageRepository chatMessageRepository;

        /**
         * Collect anonymized analytics from a conversation before it's deleted
         * This is called during the cleanup process to extract insights
         */
        @Transactional
        public void collectAnalytics(ChatConversation conversation, List<ChatMessage> messages) {
            try {
                // Create anonymized analytics record
                ChatAnalytics analytics = ChatAnalytics.builder()
                        .sessionId(UUID.randomUUID().toString()) // Anonymized session ID
                        .sessionDate(conversation.getCreatedAt().toLocalDate())
                        .sessionHour(conversation.getCreatedAt().getHour())
                        .sessionDurationMinutes(calculateSessionDuration(conversation))
                        .messageCount(messages.size())
                        .userMessageCount(countUserMessages(messages))
                        .aiMessageCount(countAiMessages(messages))
                        .topicCategories(extractTopicCategories(messages))
                        .averageResponseTimeMs(calculateAverageResponseTime(messages))
                        .conversationType(conversation.getChatType().toString())
                        .isSharedWithProvider(false) // Will be updated if shared
                        .createdAt(LocalDateTime.now())
                        .build();

                // Store analytics (this would be a separate table in real implementation)
                logAnalytics(analytics);

            } catch (Exception e) {
                log.error("Error collecting analytics for conversation: {}",
                        conversation.getConversationId(), e);
            }
        }

        /**
         * Get aggregated analytics for reporting (no individual data)
         */
        public Map<String, Object> getAggregatedAnalytics(LocalDateTime from, LocalDateTime to) {
            // In a real implementation, this would query the analytics table
            // For now, return sample aggregated data
            return Map.of(
                    "totalSessions", 0,
                    "averageSessionDuration", 0,
                    "mostCommonTopics", List.of(),
                    "peakUsageHours", List.of(),
                    "userSatisfactionScore", 0.0,
                    "systemPerformance", Map.of(
                            "averageResponseTime", 0,
                            "errorRate", 0.0
                    )
            );
        }

        /**
         * Extract topic categories from messages (anonymized)
         */
        private List<String> extractTopicCategories(List<ChatMessage> messages) {
            Set<String> topics = new HashSet<>();

            for (ChatMessage message : messages) {
                if (message.getMessageType() == ChatMessage.MessageType.USER) {
                    String content = message.getContent().toLowerCase();

                    // Categorize based on keywords (anonymized)
                    if (containsKeywords(content, Arrays.asList("medication", "drug", "pill", "prescription"))) {
                        topics.add("MEDICATION_INQUIRY");
                    }
                    if (containsKeywords(content, Arrays.asList("symptom", "pain", "ache", "hurt"))) {
                        topics.add("SYMPTOM_TRACKING");
                    }
                    if (containsKeywords(content, Arrays.asList("appointment", "visit", "doctor", "schedule"))) {
                        topics.add("APPOINTMENT_MANAGEMENT");
                    }
                    if (containsKeywords(content, Arrays.asList("allergy", "reaction", "intolerance"))) {
                        topics.add("ALLERGY_INQUIRY");
                    }
                    if (containsKeywords(content, Arrays.asList("vital", "blood pressure", "temperature", "heart rate"))) {
                        topics.add("VITALS_INQUIRY");
                    }
                    if (containsKeywords(content, Arrays.asList("mood", "mental", "anxiety", "depression"))) {
                        topics.add("MENTAL_HEALTH");
                    }
                    if (topics.isEmpty()) {
                        topics.add("GENERAL_INQUIRY");
                    }
                }
            }

            return new ArrayList<>(topics);
        }

        private boolean containsKeywords(String content, List<String> keywords) {
            return keywords.stream().anyMatch(content::contains);
        }

        private int calculateSessionDuration(ChatConversation conversation) {
            if (conversation.getUpdatedAt() != null && conversation.getCreatedAt() != null) {
                return (int) java.time.Duration.between(
                        conversation.getCreatedAt(),
                        conversation.getUpdatedAt()
                ).toMinutes();
            }
            return 0;
        }

        private int countUserMessages(List<ChatMessage> messages) {
            return (int) messages.stream()
                    .filter(msg -> msg.getMessageType() == ChatMessage.MessageType.USER)
                    .count();
        }

        private int countAiMessages(List<ChatMessage> messages) {
            return (int) messages.stream()
                    .filter(msg -> msg.getMessageType() == ChatMessage.MessageType.ASSISTANT)
                    .count();
        }

        private long calculateAverageResponseTime(List<ChatMessage> messages) {
            List<Long> responseTimes = messages.stream()
                    .filter(msg -> msg.getMessageType() == ChatMessage.MessageType.ASSISTANT)
                    .filter(msg -> msg.getProcessingTimeMs() != null)
                    .map(ChatMessage::getProcessingTimeMs)
                    .collect(Collectors.toList());

            if (responseTimes.isEmpty()) return 0;

            return responseTimes.stream()
                    .mapToLong(Long::longValue)
                    .sum() / responseTimes.size();
        }

        private void logAnalytics(ChatAnalytics analytics) {
            // In a real implementation, this would save to an analytics table
            log.info("Analytics collected: Session={}, Date={}, Duration={}min, Messages={}, Topics={}",
                    analytics.getSessionId(),
                    analytics.getSessionDate(),
                    analytics.getSessionDurationMinutes(),
                    analytics.getMessageCount(),
                    analytics.getTopicCategories());
        }

        /**
         * Analytics data model (anonymized)
         */
        @lombok.Builder
        @lombok.Data
        public static class ChatAnalytics {
            private String sessionId; // Anonymized UUID
            private java.time.LocalDate sessionDate;
            private int sessionHour;
            private int sessionDurationMinutes;
            private int messageCount;
            private int userMessageCount;
            private int aiMessageCount;
            private List<String> topicCategories;
            private long averageResponseTimeMs;
            private String conversationType;
            private boolean isSharedWithProvider;
            private LocalDateTime createdAt;
        }
    }
}
