package com.careconnect.service;

import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage;
import com.careconnect.model.UserAIConfig;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.repository.ChatMessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserAIConfigRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class MockAIChatServiceTest {

    @Mock
    private UserAIConfigRepository userAIConfigRepository;

    @Mock
    private ChatConversationRepository chatConversationRepository;

    @Mock
    private ChatMessageRepository chatMessageRepository;

    @Mock
    private PatientRepository patientRepository;

    private MockAIChatService mockAIChatService;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        mockAIChatService = new MockAIChatService(
                userAIConfigRepository,
                chatConversationRepository,
                chatMessageRepository,
                patientRepository
        );
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private ChatConversation buildConversation(String conversationId, Long patientId, Long userId, String title) {
        final ChatConversation conversation = ChatConversation.builder()
                .conversationId(conversationId)
                .patientId(patientId)
                .userId(userId)
                .title(title)
                .chatType(ChatConversation.ChatType.GENERAL_SUPPORT)
                .aiProviderUsed(UserAIConfig.AIProvider.OPENAI)
                .aiModelUsed("mock-model")
                .isActive(true)
                .totalTokensUsed(0)
                .build();
        conversation.setCreatedAt(LocalDateTime.now());
        conversation.setUpdatedAt(LocalDateTime.now());
        return conversation;
    }

    private ChatMessage buildMessage(Long id, ChatConversation conversation, ChatMessage.MessageType type, String content) {
        final ChatMessage message = ChatMessage.builder()
                .conversation(conversation)
                .messageType(type)
                .content(content)
                .tokensUsed(0)
                .processingTimeMs(100L)
                .aiModelUsed("mock-model")
                .build();
        message.setId(id);
        message.setCreatedAt(LocalDateTime.now());
        return message;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // processChat - validation errors
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_nullUserId_returnsErrorResponse")
    void processChat_nullUserId_returnsErrorResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(null);
        request.setMessage("Hello");

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getErrorMessage()).isEqualTo("User ID is required");
        assertThat(response.getErrorCode()).isEqualTo("VALIDATION_ERROR");
    }

    @Test
    @DisplayName("processChat_nullMessage_returnsErrorResponse")
    void processChat_nullMessage_returnsErrorResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setMessage(null);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getErrorMessage()).isEqualTo("Message is required");
    }

    @Test
    @DisplayName("processChat_emptyMessage_returnsErrorResponse")
    void processChat_emptyMessage_returnsErrorResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setMessage("");

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getErrorMessage()).isEqualTo("Message is required");
    }

    @Test
    @DisplayName("processChat_blankMessage_returnsErrorResponse")
    void processChat_blankMessage_returnsErrorResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setMessage("   ");

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getErrorMessage()).isEqualTo("Message is required");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // processChat - new conversation
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_noConversationId_createsNewConversation")
    void processChat_noConversationId_createsNewConversation() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("Hello there");

        final ChatConversation savedConversation = buildConversation("conv-123", 10L, 1L, "Hello there");

        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(savedConversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getConversationId()).isEqualTo("conv-123");
        assertThat(response.getMessage()).isEqualTo("Hello there");
        assertThat(response.getAiProvider()).isEqualTo("MOCK");
        assertThat(response.getModelUsed()).isEqualTo("mock-model");
        assertThat(response.getTokensUsed()).isEqualTo(0);
        assertThat(response.getProcessingTimeMs()).isEqualTo(100L);
        assertThat(response.getTemperatureUsed()).isEqualTo(0.0);
        assertThat(response.getApproachingTokenLimit()).isFalse();
        assertThat(response.getTotalTokensUsedInConversation()).isEqualTo(0);

        verify(chatConversationRepository).save(any(ChatConversation.class));
        verify(chatMessageRepository, times(2)).save(any(ChatMessage.class));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // processChat - existing conversation
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_existingConversationId_usesExistingConversation")
    void processChat_existingConversationId_usesExistingConversation() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setConversationId("existing-conv");
        request.setMessage("Follow up question");

        final ChatConversation existingConversation = buildConversation("existing-conv", 10L, 1L, "Original title");

        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("existing-conv"))
                .thenReturn(Optional.of(existingConversation));
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(2L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(4);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getConversationId()).isEqualTo("existing-conv");
        assertThat(response.getConversationTitle()).isEqualTo("Original title");
        verify(chatConversationRepository, never()).save(any(ChatConversation.class));
    }

    @Test
    @DisplayName("processChat_conversationIdNotFound_createsNewConversation")
    void processChat_conversationIdNotFound_createsNewConversation() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setConversationId("nonexistent-conv");
        request.setMessage("Hello");

        final ChatConversation newConversation = buildConversation("new-conv", 10L, 1L, "Hello");

        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("nonexistent-conv"))
                .thenReturn(Optional.empty());
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(newConversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        verify(chatConversationRepository).save(any(ChatConversation.class));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // processChat - mock response routing (generateMockResponse branches)
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_helloMessage_returnsMockGreeting")
    void processChat_helloMessage_returnsMockGreeting() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("hello");

        final ChatConversation conversation = buildConversation("c1", 10L, 1L, "hello");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("Hello!");
        assertThat(response.getAiResponse()).contains("mock AI response");
    }

    @Test
    @DisplayName("processChat_hiMessage_returnsMockGreeting")
    void processChat_hiMessage_returnsMockGreeting() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("Hi there");

        final ChatConversation conversation = buildConversation("c2", 10L, 1L, "Hi there");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("Hello!");
    }

    @Test
    @DisplayName("processChat_medicationMessage_returnsMedicationMockResponse")
    void processChat_medicationMessage_returnsMedicationMockResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("Tell me about my medication");

        final ChatConversation conversation = buildConversation("c3", 10L, 1L, "Tell me about my medication");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("mock AI assistant");
        assertThat(response.getAiResponse()).contains("medications");
    }

    @Test
    @DisplayName("processChat_medicineMessage_returnsMedicationMockResponse")
    void processChat_medicineMessage_returnsMedicationMockResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("I need medicine info");

        final ChatConversation conversation = buildConversation("c4", 10L, 1L, "I need medicine info");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("medications");
    }

    @Test
    @DisplayName("processChat_symptomMessage_returnsSymptomMockResponse")
    void processChat_symptomMessage_returnsSymptomMockResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("I have a symptom");

        final ChatConversation conversation = buildConversation("c5", 10L, 1L, "I have a symptom");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("mock response");
        assertThat(response.getAiResponse()).contains("symptoms");
    }

    @Test
    @DisplayName("processChat_painMessage_returnsSymptomMockResponse")
    void processChat_painMessage_returnsSymptomMockResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("I have pain in my back");

        final ChatConversation conversation = buildConversation("c6", 10L, 1L, "I have pain in my back");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("symptoms");
    }

    @Test
    @DisplayName("processChat_genericMessage_returnsDefaultMockResponse")
    void processChat_genericMessage_returnsDefaultMockResponse() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("What is the weather today?");

        final ChatConversation conversation = buildConversation("c7", 10L, 1L, "What is the weather today?");
        when(chatConversationRepository.save(any(ChatConversation.class))).thenReturn(conversation);
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getAiResponse()).contains("Thank you for your message");
        assertThat(response.getAiResponse()).contains("mock AI response");
        assertThat(response.getAiResponse()).contains("careconnect.deepseek.enabled=true");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // processChat - title generation
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_longMessageNoTitle_titleTruncatedTo47PlusEllipsis")
    void processChat_longMessageNoTitle_titleTruncatedTo47PlusEllipsis() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("This is a very long message that exceeds fifty characters and should be truncated for the title");


        // The title should be truncated at 47 characters + "..."
        when(chatConversationRepository.save(any(ChatConversation.class))).thenAnswer(inv -> {
            final ChatConversation saved = inv.getArgument(0);
            // Simulate persisting - verify title truncation
            assertThat(saved.getTitle().length()).isLessThanOrEqualTo(50);
            saved.setCreatedAt(LocalDateTime.now());
            saved.setUpdatedAt(LocalDateTime.now());
            return saved;
        });
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
    }

    @Test
    @DisplayName("processChat_shortMessageNoTitle_titleIsFullMessage")
    void processChat_shortMessageNoTitle_titleIsFullMessage() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("Short message");

        when(chatConversationRepository.save(any(ChatConversation.class))).thenAnswer(inv -> {
            final ChatConversation saved = inv.getArgument(0);
            assertThat(saved.getTitle()).isEqualTo("Short message");
            saved.setCreatedAt(LocalDateTime.now());
            saved.setUpdatedAt(LocalDateTime.now());
            return saved;
        });
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
    }

    @Test
    @DisplayName("processChat_requestWithTitle_usesProvidedTitle")
    void processChat_requestWithTitle_usesProvidedTitle() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage("Hello");
        request.setTitle("Custom Title");

        when(chatConversationRepository.save(any(ChatConversation.class))).thenAnswer(inv -> {
            final ChatConversation saved = inv.getArgument(0);
            assertThat(saved.getTitle()).isEqualTo("Custom Title");
            saved.setCreatedAt(LocalDateTime.now());
            saved.setUpdatedAt(LocalDateTime.now());
            return saved;
        });
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage msg = inv.getArgument(0);
            msg.setId(1L);
            return msg;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // getPatientConversations
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("getPatientConversations_patientWithConversations_returnsSummaries")
    void getPatientConversations_patientWithConversations_returnsSummaries() throws Exception {
        final ChatConversation conv1 = buildConversation("conv-1", 10L, 1L, "Conversation 1");
        final ChatConversation conv2 = buildConversation("conv-2", 10L, 1L, "Conversation 2");

        when(chatConversationRepository.findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(10L))
                .thenReturn(List.of(conv1, conv2));
        when(chatMessageRepository.countByConversation(any())).thenReturn(3);

        final List<ChatConversationSummary> summaries = mockAIChatService.getPatientConversations(10L);

        assertThat(summaries).hasSize(2);
        assertThat(summaries.get(0).getConversationId()).isEqualTo("conv-1");
        assertThat(summaries.get(0).getTitle()).isEqualTo("Conversation 1");
        assertThat(summaries.get(0).getAiProvider()).isEqualTo("OPENAI");
        assertThat(summaries.get(0).getAiModel()).isEqualTo("mock-model");
        assertThat(summaries.get(0).getTotalMessages()).isEqualTo(3);
        assertThat(summaries.get(0).getIsActive()).isTrue();
        assertThat(summaries.get(1).getConversationId()).isEqualTo("conv-2");
    }

    @Test
    @DisplayName("getPatientConversations_noConversations_returnsEmptyList")
    void getPatientConversations_noConversations_returnsEmptyList() throws Exception {
        when(chatConversationRepository.findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(99L))
                .thenReturn(List.of());

        final List<ChatConversationSummary> summaries = mockAIChatService.getPatientConversations(99L);

        assertThat(summaries).isEmpty();
    }

    @Test
    @DisplayName("getPatientConversations_nullAiProvider_returnsNullProviderInSummary")
    void getPatientConversations_nullAiProvider_returnsNullProviderInSummary() throws Exception {
        final ChatConversation conv = buildConversation("conv-null", 10L, 1L, "No Provider");
        conv.setAiProviderUsed(null);

        when(chatConversationRepository.findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(10L))
                .thenReturn(List.of(conv));
        when(chatMessageRepository.countByConversation(any())).thenReturn(1);

        final List<ChatConversationSummary> summaries = mockAIChatService.getPatientConversations(10L);

        assertThat(summaries).hasSize(1);
        assertThat(summaries.get(0).getAiProvider()).isNull();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // getConversationMessages
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("getConversationMessages_validConversationId_returnsMessages")
    void getConversationMessages_validConversationId_returnsMessages() throws Exception {
        final ChatConversation conversation = buildConversation("conv-msg", 10L, 1L, "Test");
        final ChatMessage msg1 = buildMessage(1L, conversation, ChatMessage.MessageType.USER, "Hello");
        final ChatMessage msg2 = buildMessage(2L, conversation, ChatMessage.MessageType.ASSISTANT, "Hi there");

        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("conv-msg"))
                .thenReturn(Optional.of(conversation));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(List.of(msg1, msg2));

        final List<ChatMessageSummary> messages = mockAIChatService.getConversationMessages("conv-msg");

        assertThat(messages).hasSize(2);
        assertThat(messages.get(0).getMessageId()).isEqualTo(1L);
        assertThat(messages.get(0).getMessageType()).isEqualTo(ChatMessage.MessageType.USER);
        assertThat(messages.get(0).getContent()).isEqualTo("Hello");
        assertThat(messages.get(0).getTokensUsed()).isEqualTo(0);
        assertThat(messages.get(0).getProcessingTimeMs()).isEqualTo(100L);
        assertThat(messages.get(0).getAiModelUsed()).isEqualTo("mock-model");
        assertThat(messages.get(1).getMessageId()).isEqualTo(2L);
        assertThat(messages.get(1).getContent()).isEqualTo("Hi there");
    }

    @Test
    @DisplayName("getConversationMessages_conversationNotFound_throwsException")
    void getConversationMessages_conversationNotFound_throwsException() throws Exception {
        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("nonexistent"))
                .thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class,
                () -> mockAIChatService.getConversationMessages("nonexistent"));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // getRecentMessagesForUser
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("getRecentMessagesForUser_userWithConversations_returnsRecentMessages")
    void getRecentMessagesForUser_userWithConversations_returnsRecentMessages() throws Exception {
        final ChatConversation conv = buildConversation("recent-conv", 10L, 1L, "Recent");
        final ChatMessage msg = buildMessage(1L, conv, ChatMessage.MessageType.USER, "Recent msg");

        when(chatConversationRepository.findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(1L))
                .thenReturn(List.of(conv));
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conv, 5))
                .thenReturn(List.of(msg));

        final List<ChatMessageSummary> messages = mockAIChatService.getRecentMessagesForUser(1L, 5);

        assertThat(messages).hasSize(1);
        assertThat(messages.get(0).getContent()).isEqualTo("Recent msg");
    }

    @Test
    @DisplayName("getRecentMessagesForUser_noConversations_returnsEmptyList")
    void getRecentMessagesForUser_noConversations_returnsEmptyList() throws Exception {
        when(chatConversationRepository.findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(99L))
                .thenReturn(new ArrayList<>());

        final List<ChatMessageSummary> messages = mockAIChatService.getRecentMessagesForUser(99L, 10);

        assertThat(messages).isEmpty();
    }

    @Test
    @DisplayName("getRecentMessagesForUser_multipleConversations_usesFirstOne")
    void getRecentMessagesForUser_multipleConversations_usesFirstOne() throws Exception {
        final ChatConversation conv1 = buildConversation("conv-first", 10L, 1L, "First");
        final ChatConversation conv2 = buildConversation("conv-second", 10L, 1L, "Second");
        final ChatMessage msg = buildMessage(1L, conv1, ChatMessage.MessageType.USER, "From first");

        when(chatConversationRepository.findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(1L))
                .thenReturn(List.of(conv1, conv2));
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conv1, 3))
                .thenReturn(List.of(msg));

        final List<ChatMessageSummary> messages = mockAIChatService.getRecentMessagesForUser(1L, 3);

        assertThat(messages).hasSize(1);
        assertThat(messages.get(0).getContent()).isEqualTo("From first");
        verify(chatMessageRepository).findTopNByConversationOrderByCreatedAtAsc(conv1, 3);
        verify(chatMessageRepository, never()).findTopNByConversationOrderByCreatedAtAsc(eq(conv2), anyInt());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // deactivateConversation
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("deactivateConversation_validConversationId_deactivatesConversation")
    void deactivateConversation_validConversationId_deactivatesConversation() throws Exception {
        final ChatConversation conversation = buildConversation("conv-deactivate", 10L, 1L, "To Deactivate");

        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("conv-deactivate"))
                .thenReturn(Optional.of(conversation));

        mockAIChatService.deactivateConversation("conv-deactivate");

        assertThat(conversation.getIsActive()).isFalse();
        verify(chatConversationRepository).save(conversation);
    }

    @Test
    @DisplayName("deactivateConversation_conversationNotFound_throwsException")
    void deactivateConversation_conversationNotFound_throwsException() throws Exception {
        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("nonexistent"))
                .thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class,
                () -> mockAIChatService.deactivateConversation("nonexistent"));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // buildErrorResponse - field coverage
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_errorResponse_containsRequestConversationIdAndMessage")
    void processChat_errorResponse_containsRequestConversationIdAndMessage() throws Exception {
        final ChatRequest request = new ChatRequest();
        request.setUserId(null);
        request.setConversationId("error-conv");
        request.setMessage("test message");

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getConversationId()).isEqualTo("error-conv");
        assertThat(response.getMessage()).isEqualTo("test message");
        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getTimestamp()).isNotNull();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // convertToConversationSummary - field coverage
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("getPatientConversations_allFieldsMapped_summaryContainsAllFields")
    void getPatientConversations_allFieldsMapped_summaryContainsAllFields() throws Exception {
        final ChatConversation conv = buildConversation("conv-full", 10L, 1L, "Full Test");
        conv.setChatType(ChatConversation.ChatType.MEDICAL_CONSULTATION);
        conv.setTotalTokensUsed(150);

        when(chatConversationRepository.findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(10L))
                .thenReturn(List.of(conv));
        when(chatMessageRepository.countByConversation(conv)).thenReturn(5);

        final List<ChatConversationSummary> summaries = mockAIChatService.getPatientConversations(10L);

        assertThat(summaries).hasSize(1);
        final ChatConversationSummary summary = summaries.get(0);
        assertThat(summary.getConversationId()).isEqualTo("conv-full");
        assertThat(summary.getTitle()).isEqualTo("Full Test");
        assertThat(summary.getChatType()).isEqualTo(ChatConversation.ChatType.MEDICAL_CONSULTATION);
        assertThat(summary.getAiProvider()).isEqualTo("OPENAI");
        assertThat(summary.getAiModel()).isEqualTo("mock-model");
        assertThat(summary.getTotalMessages()).isEqualTo(5);
        assertThat(summary.getTotalTokensUsed()).isEqualTo(150);
        assertThat(summary.getLastMessageAt()).isNotNull();
        assertThat(summary.getCreatedAt()).isNotNull();
        assertThat(summary.getIsActive()).isTrue();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // convertToMessageSummary - field coverage
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("getConversationMessages_allFieldsMapped_messageSummaryContainsAllFields")
    void getConversationMessages_allFieldsMapped_messageSummaryContainsAllFields() throws Exception {
        final ChatConversation conversation = buildConversation("conv-fields", 10L, 1L, "Field Test");
        final ChatMessage msg = buildMessage(42L, conversation, ChatMessage.MessageType.ASSISTANT, "Full response");

        when(chatConversationRepository.findByConversationIdAndIsActiveTrue("conv-fields"))
                .thenReturn(Optional.of(conversation));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(List.of(msg));

        final List<ChatMessageSummary> messages = mockAIChatService.getConversationMessages("conv-fields");

        assertThat(messages).hasSize(1);
        final ChatMessageSummary summary = messages.get(0);
        assertThat(summary.getMessageId()).isEqualTo(42L);
        assertThat(summary.getMessageType()).isEqualTo(ChatMessage.MessageType.ASSISTANT);
        assertThat(summary.getContent()).isEqualTo("Full response");
        assertThat(summary.getTokensUsed()).isEqualTo(0);
        assertThat(summary.getProcessingTimeMs()).isEqualTo(100L);
        assertThat(summary.getAiModelUsed()).isEqualTo("mock-model");
        assertThat(summary.getCreatedAt()).isNotNull();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // processChat - message exactly 50 chars for title boundary
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("processChat_messageExactly50Chars_titleIsFullMessage")
    void processChat_messageExactly50Chars_titleIsFullMessage() throws Exception {
        // Exactly 50 characters: not > 50, so should use full message
        final String msg50 = "12345678901234567890123456789012345678901234567890";
        assertThat(msg50.length()).isEqualTo(50);

        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage(msg50);

        when(chatConversationRepository.save(any(ChatConversation.class))).thenAnswer(inv -> {
            final ChatConversation saved = inv.getArgument(0);
            assertThat(saved.getTitle()).isEqualTo(msg50);
            saved.setCreatedAt(LocalDateTime.now());
            saved.setUpdatedAt(LocalDateTime.now());
            return saved;
        });
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage m = inv.getArgument(0);
            m.setId(1L);
            return m;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
    }

    @Test
    @DisplayName("processChat_message51Chars_titleIsTruncated")
    void processChat_message51Chars_titleIsTruncated() throws Exception {
        // 51 characters: > 50, so title should be truncated to 47 + "..."
        final String msg51 = "123456789012345678901234567890123456789012345678901";
        assertThat(msg51.length()).isEqualTo(51);

        final ChatRequest request = new ChatRequest();
        request.setUserId(1L);
        request.setPatientId(10L);
        request.setMessage(msg51);

        when(chatConversationRepository.save(any(ChatConversation.class))).thenAnswer(inv -> {
            final ChatConversation saved = inv.getArgument(0);
            assertThat(saved.getTitle()).isEqualTo(msg51.substring(0, 47) + "...");
            saved.setCreatedAt(LocalDateTime.now());
            saved.setUpdatedAt(LocalDateTime.now());
            return saved;
        });
        when(chatMessageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            final ChatMessage m = inv.getArgument(0);
            m.setId(1L);
            return m;
        });
        when(chatMessageRepository.countByConversation(any())).thenReturn(2);

        final ChatResponse response = mockAIChatService.processChat(request);

        assertThat(response.getSuccess()).isTrue();
    }
}
