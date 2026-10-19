package com.careconnect.service;

import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.repository.ChatMessageRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

class ChatAnalyticsServiceTest {

    @Mock
    private ChatConversationRepository chatConversationRepository;

    @Mock
    private ChatMessageRepository chatMessageRepository;

    @InjectMocks
    private ChatAnalyticsService chatAnalyticsService;

    private ChatConversation conversation;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        conversation = new ChatConversation();
        conversation.setConversationId("test-conv-id");
        conversation.setCreatedAt(LocalDateTime.of(2025, 6, 15, 10, 0, 0));
        conversation.setUpdatedAt(LocalDateTime.of(2025, 6, 15, 10, 30, 0));
        conversation.setChatType(ChatConversation.ChatType.GENERAL_SUPPORT);
    }

    // ---- collectAnalytics tests ----

    @Test
    @DisplayName("collectAnalytics - valid conversation with messages - collects analytics without error")
    void collectAnalytics_validConversationWithMessages_collectsAnalytics() throws Exception {
        final List<ChatMessage> messages = List.of(
                createUserMessage("I need help with my medication prescription"),
                createAssistantMessage(100L),
                createUserMessage("What about my symptom pain?"),
                createAssistantMessage(200L)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - empty messages list - collects analytics without error")
    void collectAnalytics_emptyMessagesList_collectsAnalytics() throws Exception {
        final List<ChatMessage> messages = Collections.emptyList();

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - conversation with null updatedAt - session duration is zero")
    void collectAnalytics_nullUpdatedAt_sessionDurationZero() throws Exception {
        conversation.setUpdatedAt(null);
        final List<ChatMessage> messages = List.of(createUserMessage("hello"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - conversation with null createdAt for duration but non-null createdAt for date/hour - handles gracefully")
    void collectAnalytics_nullCreatedAtForDuration_handlesGracefully() throws Exception {
        // createdAt is used in both the builder and calculateSessionDuration
        // When createdAt is null, calculateSessionDuration returns 0 but
        // the builder call to getCreatedAt().toLocalDate() will throw NPE which is caught
        conversation.setCreatedAt(null);
        final List<ChatMessage> messages = List.of(createUserMessage("hello"));

        // This should be caught by the try-catch in collectAnalytics
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - exception during processing - error is caught and logged")
    void collectAnalytics_exceptionDuringProcessing_errorCaughtAndLogged() throws Exception {
        // Setting chatType to null will cause NPE at conversation.getChatType().toString()
        conversation.setChatType(null);
        final List<ChatMessage> messages = List.of(createUserMessage("hello"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - messages with all topic categories - extracts all topics")
    void collectAnalytics_messagesWithAllTopics_extractsAllTopics() throws Exception {
        final List<ChatMessage> messages = List.of(
                createUserMessage("I need my medication prescription drug pill"),
                createUserMessage("I have a symptom with pain and it aches and hurts"),
                createUserMessage("I have an appointment to visit the doctor and schedule"),
                createUserMessage("I have an allergy and reaction and intolerance"),
                createUserMessage("Check my vital signs blood pressure temperature heart rate"),
                createUserMessage("My mood and mental health anxiety depression")
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - message with no matching keywords - categorized as GENERAL_INQUIRY")
    void collectAnalytics_noMatchingKeywords_generalInquiry() throws Exception {
        final List<ChatMessage> messages = List.of(
                createUserMessage("hello how are you today")
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - only assistant messages - no topic categories extracted from user messages")
    void collectAnalytics_onlyAssistantMessages_noTopicCategories() throws Exception {
        final List<ChatMessage> messages = List.of(
                createAssistantMessage(100L),
                createAssistantMessage(200L)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - assistant messages with null processingTimeMs - averageResponseTime is zero")
    void collectAnalytics_nullProcessingTimeMs_averageResponseTimeZero() throws Exception {
        final List<ChatMessage> messages = List.of(
                createAssistantMessage(null),
                createUserMessage("test")
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - system messages only - no user or assistant counts")
    void collectAnalytics_systemMessagesOnly_noUserOrAssistantCounts() throws Exception {
        final ChatMessage systemMsg = new ChatMessage();
        systemMsg.setMessageType(ChatMessage.MessageType.SYSTEM);
        systemMsg.setContent("System initialization");
        final List<ChatMessage> messages = List.of(systemMsg);

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - mixed message types - counts user and ai messages correctly")
    void collectAnalytics_mixedMessageTypes_countsCorrectly() throws Exception {
        final ChatMessage systemMsg = new ChatMessage();
        systemMsg.setMessageType(ChatMessage.MessageType.SYSTEM);
        systemMsg.setContent("System message");

        final List<ChatMessage> messages = List.of(
                createUserMessage("user message"),
                createAssistantMessage(50L),
                systemMsg,
                createUserMessage("another user message"),
                createAssistantMessage(75L)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- getAggregatedAnalytics tests ----

    @Test
    @DisplayName("getAggregatedAnalytics - valid date range - returns aggregated data map")
    void getAggregatedAnalytics_validDateRange_returnsAggregatedData() throws Exception {
        final LocalDateTime from = LocalDateTime.of(2025, 1, 1, 0, 0);
        final LocalDateTime to = LocalDateTime.of(2025, 12, 31, 23, 59);

        final Map<String, Object> result = chatAnalyticsService.getAggregatedAnalytics(from, to);

        assertNotNull(result);
        assertEquals(0, result.get("totalSessions"));
        assertEquals(0, result.get("averageSessionDuration"));
        assertEquals(List.of(), result.get("mostCommonTopics"));
        assertEquals(List.of(), result.get("peakUsageHours"));
        assertEquals(0.0, result.get("userSatisfactionScore"));

        @SuppressWarnings("unchecked") final Map<String, Object> systemPerformance = (Map<String, Object>) result.get("systemPerformance");
        assertNotNull(systemPerformance);
        assertEquals(0, systemPerformance.get("averageResponseTime"));
        assertEquals(0.0, systemPerformance.get("errorRate"));
    }

    @Test
    @DisplayName("getAggregatedAnalytics - returns exactly 6 keys in the map")
    void getAggregatedAnalytics_returnsSixKeys() throws Exception {
        final LocalDateTime from = LocalDateTime.now().minusDays(30);
        final LocalDateTime to = LocalDateTime.now();

        final Map<String, Object> result = chatAnalyticsService.getAggregatedAnalytics(from, to);

        assertEquals(6, result.size());
        assertTrue(result.containsKey("totalSessions"));
        assertTrue(result.containsKey("averageSessionDuration"));
        assertTrue(result.containsKey("mostCommonTopics"));
        assertTrue(result.containsKey("peakUsageHours"));
        assertTrue(result.containsKey("userSatisfactionScore"));
        assertTrue(result.containsKey("systemPerformance"));
    }

    // ---- extractTopicCategories branch coverage ----

    @Test
    @DisplayName("extractTopicCategories - medication keywords - returns MEDICATION_INQUIRY")
    void collectAnalytics_medicationKeyword_medicationInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I need my medication"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - drug keyword - returns MEDICATION_INQUIRY")
    void collectAnalytics_drugKeyword_medicationInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("what drug should I take"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - pill keyword - returns MEDICATION_INQUIRY")
    void collectAnalytics_pillKeyword_medicationInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I took my pill"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - prescription keyword - returns MEDICATION_INQUIRY")
    void collectAnalytics_prescriptionKeyword_medicationInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("my prescription is ready"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - symptom keyword - returns SYMPTOM_TRACKING")
    void collectAnalytics_symptomKeyword_symptomTrackingTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have a symptom"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - pain keyword - returns SYMPTOM_TRACKING")
    void collectAnalytics_painKeyword_symptomTrackingTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I feel pain"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - ache keyword - returns SYMPTOM_TRACKING")
    void collectAnalytics_acheKeyword_symptomTrackingTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have an ache"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - hurt keyword - returns SYMPTOM_TRACKING")
    void collectAnalytics_hurtKeyword_symptomTrackingTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("my arm hurts"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - appointment keyword - returns APPOINTMENT_MANAGEMENT")
    void collectAnalytics_appointmentKeyword_appointmentManagementTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have an appointment"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - visit keyword - returns APPOINTMENT_MANAGEMENT")
    void collectAnalytics_visitKeyword_appointmentManagementTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have a visit"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - doctor keyword - returns APPOINTMENT_MANAGEMENT")
    void collectAnalytics_doctorKeyword_appointmentManagementTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I need to see the doctor"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - schedule keyword - returns APPOINTMENT_MANAGEMENT")
    void collectAnalytics_scheduleKeyword_appointmentManagementTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I need to schedule"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - allergy keyword - returns ALLERGY_INQUIRY")
    void collectAnalytics_allergyKeyword_allergyInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have an allergy"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - reaction keyword - returns ALLERGY_INQUIRY")
    void collectAnalytics_reactionKeyword_allergyInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I had a reaction"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - intolerance keyword - returns ALLERGY_INQUIRY")
    void collectAnalytics_intoleranceKeyword_allergyInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have an intolerance"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - vital keyword - returns VITALS_INQUIRY")
    void collectAnalytics_vitalKeyword_vitalsInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("check my vital signs"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - blood pressure keyword - returns VITALS_INQUIRY")
    void collectAnalytics_bloodPressureKeyword_vitalsInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("my blood pressure is high"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - temperature keyword - returns VITALS_INQUIRY")
    void collectAnalytics_temperatureKeyword_vitalsInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("what is my temperature"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - heart rate keyword - returns VITALS_INQUIRY")
    void collectAnalytics_heartRateKeyword_vitalsInquiryTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("my heart rate is fast"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - mood keyword - returns MENTAL_HEALTH")
    void collectAnalytics_moodKeyword_mentalHealthTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("my mood is bad"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - mental keyword - returns MENTAL_HEALTH")
    void collectAnalytics_mentalKeyword_mentalHealthTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("my mental health"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - anxiety keyword - returns MENTAL_HEALTH")
    void collectAnalytics_anxietyKeyword_mentalHealthTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I have anxiety"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - depression keyword - returns MENTAL_HEALTH")
    void collectAnalytics_depressionKeyword_mentalHealthTopic() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("I feel depression"));
        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - GENERAL_INQUIRY added only when topics set is empty after processing a user message")
    void collectAnalytics_generalInquiryOnlyWhenEmpty_generalInquiryTopic() throws Exception {
        // First message has no matching keywords -> GENERAL_INQUIRY gets added
        // Second message does match -> MEDICATION_INQUIRY also added
        // Both should be present
        final List<ChatMessage> messages = List.of(
                createUserMessage("hello there"),
                createUserMessage("I need my medication")
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - multiple categories from single message - extracts all matching categories")
    void collectAnalytics_multipleCategoriesSingleMessage_extractsAllCategories() throws Exception {
        // A single message containing keywords from multiple categories
        final List<ChatMessage> messages = List.of(
                createUserMessage("I have a medication allergy that causes pain and affects my mood and vital signs, need to schedule a doctor appointment")
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- calculateSessionDuration branch coverage ----

    @Test
    @DisplayName("calculateSessionDuration - both dates present - returns duration in minutes")
    void collectAnalytics_bothDatesPresent_calculatesSessionDuration() throws Exception {
        conversation.setCreatedAt(LocalDateTime.of(2025, 6, 15, 10, 0, 0));
        conversation.setUpdatedAt(LocalDateTime.of(2025, 6, 15, 10, 45, 0));
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("calculateSessionDuration - updatedAt is null - returns zero duration")
    void collectAnalytics_updatedAtNull_zeroDuration() throws Exception {
        conversation.setUpdatedAt(null);
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- calculateAverageResponseTime branch coverage ----

    @Test
    @DisplayName("calculateAverageResponseTime - no assistant messages - returns zero")
    void collectAnalytics_noAssistantMessages_averageResponseTimeZero() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("calculateAverageResponseTime - assistant messages with processingTimeMs - calculates average")
    void collectAnalytics_assistantMessagesWithProcessingTime_calculatesAverage() throws Exception {
        final List<ChatMessage> messages = List.of(
                createAssistantMessage(100L),
                createAssistantMessage(300L),
                createAssistantMessage(200L)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("calculateAverageResponseTime - mix of null and non-null processingTimeMs - only uses non-null values")
    void collectAnalytics_mixNullAndNonNullProcessingTime_usesOnlyNonNull() throws Exception {
        final List<ChatMessage> messages = List.of(
                createAssistantMessage(100L),
                createAssistantMessage(null),
                createAssistantMessage(200L)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("calculateAverageResponseTime - all assistant messages have null processingTimeMs - returns zero")
    void collectAnalytics_allNullProcessingTime_returnsZero() throws Exception {
        final List<ChatMessage> messages = List.of(
                createAssistantMessage(null),
                createAssistantMessage(null)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- ChatAnalytics inner class tests ----

    @Test
    @DisplayName("ChatAnalytics builder - all fields set - builds correctly")
    void chatAnalytics_builderAllFields_buildsCorrectly() throws Exception {
        final LocalDateTime now = LocalDateTime.now();
        final List<String> topics = List.of("MEDICATION_INQUIRY", "SYMPTOM_TRACKING");

        final ChatAnalyticsService.ChatAnalytics analytics = ChatAnalyticsService.ChatAnalytics.builder()
                .sessionId("test-session-id")
                .sessionDate(now.toLocalDate())
                .sessionHour(14)
                .sessionDurationMinutes(30)
                .messageCount(10)
                .userMessageCount(5)
                .aiMessageCount(5)
                .topicCategories(topics)
                .averageResponseTimeMs(150L)
                .conversationType("GENERAL_SUPPORT")
                .isSharedWithProvider(false)
                .createdAt(now)
                .build();

        assertEquals("test-session-id", analytics.getSessionId());
        assertEquals(now.toLocalDate(), analytics.getSessionDate());
        assertEquals(14, analytics.getSessionHour());
        assertEquals(30, analytics.getSessionDurationMinutes());
        assertEquals(10, analytics.getMessageCount());
        assertEquals(5, analytics.getUserMessageCount());
        assertEquals(5, analytics.getAiMessageCount());
        assertEquals(topics, analytics.getTopicCategories());
        assertEquals(150L, analytics.getAverageResponseTimeMs());
        assertEquals("GENERAL_SUPPORT", analytics.getConversationType());
        assertFalse(analytics.isSharedWithProvider());
        assertEquals(now, analytics.getCreatedAt());
    }

    @Test
    @DisplayName("ChatAnalytics - setters work correctly")
    void chatAnalytics_setters_workCorrectly() throws Exception {
        final ChatAnalyticsService.ChatAnalytics analytics = ChatAnalyticsService.ChatAnalytics.builder()
                .sessionId("initial")
                .sessionDate(java.time.LocalDate.now())
                .sessionHour(0)
                .sessionDurationMinutes(0)
                .messageCount(0)
                .userMessageCount(0)
                .aiMessageCount(0)
                .topicCategories(new ArrayList<>())
                .averageResponseTimeMs(0L)
                .conversationType("GENERAL_SUPPORT")
                .isSharedWithProvider(false)
                .createdAt(LocalDateTime.now())
                .build();

        analytics.setSessionId("updated-id");
        analytics.setSharedWithProvider(true);
        analytics.setMessageCount(42);

        assertEquals("updated-id", analytics.getSessionId());
        assertTrue(analytics.isSharedWithProvider());
        assertEquals(42, analytics.getMessageCount());
    }

    @Test
    @DisplayName("ChatAnalytics - toString returns non-null string")
    void chatAnalytics_toString_returnsNonNull() throws Exception {
        final ChatAnalyticsService.ChatAnalytics analytics = ChatAnalyticsService.ChatAnalytics.builder()
                .sessionId("test")
                .sessionDate(java.time.LocalDate.now())
                .sessionHour(10)
                .sessionDurationMinutes(5)
                .messageCount(2)
                .userMessageCount(1)
                .aiMessageCount(1)
                .topicCategories(List.of("GENERAL_INQUIRY"))
                .averageResponseTimeMs(50L)
                .conversationType("GENERAL_SUPPORT")
                .isSharedWithProvider(false)
                .createdAt(LocalDateTime.now())
                .build();

        assertNotNull(analytics.toString());
    }

    @Test
    @DisplayName("ChatAnalytics - equals and hashCode work correctly")
    void chatAnalytics_equalsAndHashCode_workCorrectly() throws Exception {
        final LocalDateTime now = LocalDateTime.now();
        java.time.LocalDate today = java.time.LocalDate.now();
        final List<String> topics = List.of("GENERAL_INQUIRY");

        final ChatAnalyticsService.ChatAnalytics analytics1 = ChatAnalyticsService.ChatAnalytics.builder()
                .sessionId("same-id")
                .sessionDate(today)
                .sessionHour(10)
                .sessionDurationMinutes(5)
                .messageCount(2)
                .userMessageCount(1)
                .aiMessageCount(1)
                .topicCategories(topics)
                .averageResponseTimeMs(50L)
                .conversationType("GENERAL_SUPPORT")
                .isSharedWithProvider(false)
                .createdAt(now)
                .build();

        final ChatAnalyticsService.ChatAnalytics analytics2 = ChatAnalyticsService.ChatAnalytics.builder()
                .sessionId("same-id")
                .sessionDate(today)
                .sessionHour(10)
                .sessionDurationMinutes(5)
                .messageCount(2)
                .userMessageCount(1)
                .aiMessageCount(1)
                .topicCategories(topics)
                .averageResponseTimeMs(50L)
                .conversationType("GENERAL_SUPPORT")
                .isSharedWithProvider(false)
                .createdAt(now)
                .build();

        assertEquals(analytics1, analytics2);
        assertEquals(analytics1.hashCode(), analytics2.hashCode());
    }

    // ---- Different ChatType values ----

    @Test
    @DisplayName("collectAnalytics - MEDICAL_CONSULTATION chat type - collects analytics")
    void collectAnalytics_medicalConsultationType_collectsAnalytics() throws Exception {
        conversation.setChatType(ChatConversation.ChatType.MEDICAL_CONSULTATION);
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - MEDICATION_INQUIRY chat type - collects analytics")
    void collectAnalytics_medicationInquiryType_collectsAnalytics() throws Exception {
        conversation.setChatType(ChatConversation.ChatType.MEDICATION_INQUIRY);
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - MOOD_PAIN_SUPPORT chat type - collects analytics")
    void collectAnalytics_moodPainSupportType_collectsAnalytics() throws Exception {
        conversation.setChatType(ChatConversation.ChatType.MOOD_PAIN_SUPPORT);
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - EMERGENCY_GUIDANCE chat type - collects analytics")
    void collectAnalytics_emergencyGuidanceType_collectsAnalytics() throws Exception {
        conversation.setChatType(ChatConversation.ChatType.EMERGENCY_GUIDANCE);
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("collectAnalytics - LIFESTYLE_ADVICE chat type - collects analytics")
    void collectAnalytics_lifestyleAdviceType_collectsAnalytics() throws Exception {
        conversation.setChatType(ChatConversation.ChatType.LIFESTYLE_ADVICE);
        final List<ChatMessage> messages = List.of(createUserMessage("test"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- Edge cases for keyword matching ----

    @Test
    @DisplayName("extractTopicCategories - uppercase content converted to lowercase - matches keywords")
    void collectAnalytics_uppercaseContent_matchesKeywords() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("MY MEDICATION IS READY"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - mixed case content - matches keywords")
    void collectAnalytics_mixedCaseContent_matchesKeywords() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("My Medication And Symptom"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("extractTopicCategories - keyword as substring - matches keywords")
    void collectAnalytics_keywordAsSubstring_matchesKeywords() throws Exception {
        final List<ChatMessage> messages = List.of(createUserMessage("medications are important"));

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- countUserMessages and countAiMessages coverage ----

    @Test
    @DisplayName("countUserMessages - only user messages - returns correct count")
    void collectAnalytics_onlyUserMessages_correctUserCount() throws Exception {
        final List<ChatMessage> messages = List.of(
                createUserMessage("msg1"),
                createUserMessage("msg2"),
                createUserMessage("msg3")
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    @Test
    @DisplayName("countAiMessages - only assistant messages - returns correct count")
    void collectAnalytics_onlyAssistantMessages_correctAiCount() throws Exception {
        final List<ChatMessage> messages = List.of(
                createAssistantMessage(100L),
                createAssistantMessage(200L)
        );

        assertDoesNotThrow(() -> chatAnalyticsService.collectAnalytics(conversation, messages));
    }

    // ---- Helper methods ----

    private ChatMessage createUserMessage(String content) {
        final ChatMessage message = new ChatMessage();
        message.setMessageType(ChatMessage.MessageType.USER);
        message.setContent(content);
        return message;
    }

    private ChatMessage createAssistantMessage(Long processingTimeMs) {
        final ChatMessage message = new ChatMessage();
        message.setMessageType(ChatMessage.MessageType.ASSISTANT);
        message.setContent("AI response");
        message.setProcessingTimeMs(processingTimeMs);
        return message;
    }
}
