package com.careconnect.service;

import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage.MessageType;
import com.careconnect.repository.ChatMessageRepository;
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.ToolExecutionResultMessage;
import dev.langchain4j.data.message.UserMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DatabaseChatMemoryTest {

    private static final int MAX_MESSAGES = 10;
    @Mock
    private ChatMessageRepository chatMessageRepository;
    private ChatConversation conversation;
    private DatabaseChatMemory chatMemory;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        conversation = ChatConversation.builder()
                .id(1L)
                .conversationId("conv-uuid-123")
                .patientId(100L)
                .userId(200L)
                .build();

        chatMemory = new DatabaseChatMemory(chatMessageRepository, conversation, MAX_MESSAGES);
    }

    // ========================================================================
    // id()
    // ========================================================================

    @Test
    @DisplayName("id_returnsConversationId_fromConversationObject")
    void id_returnsConversationId_fromConversationObject() throws Exception {
        final Object result = chatMemory.id();

        assertEquals("conv-uuid-123", result);
    }

    // ========================================================================
    // add()
    // ========================================================================

    @Test
    @DisplayName("add_systemMessage_savesWithSystemTypeAndCorrectContent")
    void add_systemMessage_savesWithSystemTypeAndCorrectContent() throws Exception {
        final SystemMessage message = SystemMessage.from("You are a helpful assistant");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(new ArrayList<>());

        chatMemory.add(message);

        final ArgumentCaptor<com.careconnect.model.ChatMessage> captor =
                ArgumentCaptor.forClass(com.careconnect.model.ChatMessage.class);
        verify(chatMessageRepository).save(captor.capture());

        com.careconnect.model.ChatMessage saved = captor.getValue();
        assertEquals(MessageType.SYSTEM, saved.getMessageType());
        assertEquals("You are a helpful assistant", saved.getContent());
        assertSame(conversation, saved.getConversation());
    }

    @Test
    @DisplayName("add_userMessage_savesWithUserTypeAndCorrectContent")
    void add_userMessage_savesWithUserTypeAndCorrectContent() throws Exception {
        final UserMessage message = UserMessage.from("Hello doctor");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(new ArrayList<>());

        chatMemory.add(message);

        final ArgumentCaptor<com.careconnect.model.ChatMessage> captor =
                ArgumentCaptor.forClass(com.careconnect.model.ChatMessage.class);
        verify(chatMessageRepository).save(captor.capture());

        com.careconnect.model.ChatMessage saved = captor.getValue();
        assertEquals(MessageType.USER, saved.getMessageType());
        assertEquals("Hello doctor", saved.getContent());
    }

    @Test
    @DisplayName("add_aiMessage_savesWithAssistantTypeAndCorrectContent")
    void add_aiMessage_savesWithAssistantTypeAndCorrectContent() throws Exception {
        final AiMessage message = AiMessage.from("I can help you with that");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(new ArrayList<>());

        chatMemory.add(message);

        final ArgumentCaptor<com.careconnect.model.ChatMessage> captor =
                ArgumentCaptor.forClass(com.careconnect.model.ChatMessage.class);
        verify(chatMessageRepository).save(captor.capture());

        com.careconnect.model.ChatMessage saved = captor.getValue();
        assertEquals(MessageType.ASSISTANT, saved.getMessageType());
        assertEquals("I can help you with that", saved.getContent());
    }

    @Test
    @DisplayName("add_unknownMessageType_fallsBackToUserTypeWithToStringContent")
    void add_unknownMessageType_fallsBackToUserTypeWithToStringContent() throws Exception {
        // ToolExecutionResultMessage exercises the else branch (not System/User/Ai)
        final ToolExecutionResultMessage message = ToolExecutionResultMessage.from("tool-1", "tool-name", "result-text");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(new ArrayList<>());

        chatMemory.add(message);

        final ArgumentCaptor<com.careconnect.model.ChatMessage> captor =
                ArgumentCaptor.forClass(com.careconnect.model.ChatMessage.class);
        verify(chatMessageRepository).save(captor.capture());

        com.careconnect.model.ChatMessage saved = captor.getValue();
        assertEquals(MessageType.USER, saved.getMessageType());
        assertNotNull(saved.getContent());
        assertFalse(saved.getContent().isEmpty());
    }

    @Test
    @DisplayName("add_exceedsMaxMessages_cleansUpOldMessages")
    void add_exceedsMaxMessages_cleansUpOldMessages() throws Exception {
        final UserMessage message = UserMessage.from("New message");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        // Create more messages than maxMessages
        final List<com.careconnect.model.ChatMessage> allMessages = new ArrayList<>();
        for (int i = 0; i < MAX_MESSAGES + 3; i++) {
            com.careconnect.model.ChatMessage msg = com.careconnect.model.ChatMessage.builder()
                    .id((long) i)
                    .conversation(conversation)
                    .messageType(MessageType.USER)
                    .content("Message " + i)
                    .build();
            allMessages.add(msg);
        }
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(allMessages);

        chatMemory.add(message);

        // Verify deleteAll was called with the oldest 3 messages
        @SuppressWarnings("unchecked") final ArgumentCaptor<List<com.careconnect.model.ChatMessage>> deleteCaptor =
                ArgumentCaptor.forClass(List.class);
        verify(chatMessageRepository).deleteAll(deleteCaptor.capture());
        assertEquals(3, deleteCaptor.getValue().size());
    }

    @Test
    @DisplayName("add_withinLimit_noCleanup")
    void add_withinLimit_noCleanup() throws Exception {
        final UserMessage message = UserMessage.from("Hello");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        // Fewer messages than max
        final List<com.careconnect.model.ChatMessage> allMessages = new ArrayList<>();
        for (int i = 0; i < MAX_MESSAGES - 2; i++) {
            com.careconnect.model.ChatMessage msg = com.careconnect.model.ChatMessage.builder()
                    .id((long) i)
                    .conversation(conversation)
                    .messageType(MessageType.USER)
                    .content("Msg " + i)
                    .build();
            allMessages.add(msg);
        }
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(allMessages);

        chatMemory.add(message);

        verify(chatMessageRepository, never()).deleteAll(anyList());
    }

    @Test
    @DisplayName("add_repositorySaveThrowsException_wrapsInRuntimeException")
    void add_repositorySaveThrowsException_wrapsInRuntimeException() throws Exception {
        final UserMessage message = UserMessage.from("Hello");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenThrow(new RuntimeException("DB connection error"));

        final RuntimeException thrown = assertThrows(RuntimeException.class, () -> chatMemory.add(message));
        assertTrue(thrown.getMessage().contains("Failed to persist chat message"));
        assertNotNull(thrown.getCause());
    }

    @Test
    @DisplayName("add_cleanupThrowsException_swallowedSilentlyAddStillSucceeds")
    void add_cleanupThrowsException_swallowedSilentlyAddStillSucceeds() throws Exception {
        final UserMessage message = UserMessage.from("Hello");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenThrow(new RuntimeException("Cleanup DB error"));

        // Should not throw -- cleanup errors are caught internally
        assertDoesNotThrow(() -> chatMemory.add(message));

        verify(chatMessageRepository).save(any(com.careconnect.model.ChatMessage.class));
    }

    // ========================================================================
    // messages()
    // ========================================================================

    @Test
    @DisplayName("messages_returnsConvertedLangChain4jMessages_inOrder")
    void messages_returnsConvertedLangChain4jMessages_inOrder() throws Exception {
        com.careconnect.model.ChatMessage sysMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.SYSTEM)
                .content("System prompt")
                .build();
        com.careconnect.model.ChatMessage userMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.USER)
                .content("User question")
                .build();
        com.careconnect.model.ChatMessage assistantMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.ASSISTANT)
                .content("AI answer")
                .build();

        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenReturn(List.of(sysMsg, userMsg, assistantMsg));

        final List<ChatMessage> result = chatMemory.messages();

        assertEquals(3, result.size());
        assertInstanceOf(SystemMessage.class, result.get(0));
        assertEquals("System prompt", ((SystemMessage) result.get(0)).text());
        assertInstanceOf(UserMessage.class, result.get(1));
        assertEquals("User question", ((UserMessage) result.get(1)).singleText());
        assertInstanceOf(AiMessage.class, result.get(2));
        assertEquals("AI answer", ((AiMessage) result.get(2)).text());
    }

    @Test
    @DisplayName("messages_emptyDatabase_returnsEmptyList")
    void messages_emptyDatabase_returnsEmptyList() throws Exception {
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenReturn(Collections.emptyList());

        final List<ChatMessage> result = chatMemory.messages();

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("messages_nullConversionResultFiltered_returnsOnlyNonNull")
    void messages_nullConversionResultFiltered_returnsOnlyNonNull() throws Exception {
        // We test with a valid message type to verify the filter works;
        // the null path (default branch) is effectively unreachable with
        // the current 3-value enum but the filter logic is exercised.
        com.careconnect.model.ChatMessage validMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.USER)
                .content("Hello")
                .build();

        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenReturn(List.of(validMsg));

        final List<ChatMessage> result = chatMemory.messages();

        assertEquals(1, result.size());
        assertInstanceOf(UserMessage.class, result.get(0));
    }

    @Test
    @DisplayName("messages_repositoryThrowsException_returnsEmptyList")
    void messages_repositoryThrowsException_returnsEmptyList() throws Exception {
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenThrow(new RuntimeException("DB is down"));

        final List<ChatMessage> result = chatMemory.messages();

        assertTrue(result.isEmpty());
    }

    // ========================================================================
    // clear()
    // ========================================================================

    @Test
    @DisplayName("clear_deletesAllMessages_forTheConversation")
    void clear_deletesAllMessages_forTheConversation() throws Exception {
        final List<com.careconnect.model.ChatMessage> messages = List.of(
                com.careconnect.model.ChatMessage.builder()
                        .id(1L)
                        .conversation(conversation)
                        .messageType(MessageType.USER)
                        .content("msg1")
                        .build(),
                com.careconnect.model.ChatMessage.builder()
                        .id(2L)
                        .conversation(conversation)
                        .messageType(MessageType.ASSISTANT)
                        .content("msg2")
                        .build()
        );
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(messages);

        chatMemory.clear();

        verify(chatMessageRepository).deleteAll(messages);
    }

    @Test
    @DisplayName("clear_noMessages_callsDeleteAllWithEmptyList")
    void clear_noMessages_callsDeleteAllWithEmptyList() throws Exception {
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(Collections.emptyList());

        chatMemory.clear();

        verify(chatMessageRepository).deleteAll(Collections.emptyList());
    }

    @Test
    @DisplayName("clear_repositoryThrowsException_wrapsInRuntimeException")
    void clear_repositoryThrowsException_wrapsInRuntimeException() throws Exception {
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenThrow(new RuntimeException("DB error"));

        final RuntimeException thrown = assertThrows(RuntimeException.class, () -> chatMemory.clear());
        assertTrue(thrown.getMessage().contains("Failed to clear chat history"));
    }

    // ========================================================================
    // convertToLangchainMessage (via messages())
    // ========================================================================

    @Test
    @DisplayName("convertToLangchainMessage_systemType_returnsSystemMessage")
    void convertToLangchainMessage_systemType_returnsSystemMessage() throws Exception {
        com.careconnect.model.ChatMessage dbMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.SYSTEM)
                .content("Be helpful")
                .build();
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenReturn(List.of(dbMsg));

        final List<ChatMessage> result = chatMemory.messages();

        assertEquals(1, result.size());
        assertInstanceOf(SystemMessage.class, result.get(0));
        assertEquals("Be helpful", ((SystemMessage) result.get(0)).text());
    }

    @Test
    @DisplayName("convertToLangchainMessage_userType_returnsUserMessage")
    void convertToLangchainMessage_userType_returnsUserMessage() throws Exception {
        com.careconnect.model.ChatMessage dbMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.USER)
                .content("What is my medication?")
                .build();
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenReturn(List.of(dbMsg));

        final List<ChatMessage> result = chatMemory.messages();

        assertEquals(1, result.size());
        assertInstanceOf(UserMessage.class, result.get(0));
        assertEquals("What is my medication?", ((UserMessage) result.get(0)).singleText());
    }

    @Test
    @DisplayName("convertToLangchainMessage_assistantType_returnsAiMessage")
    void convertToLangchainMessage_assistantType_returnsAiMessage() throws Exception {
        com.careconnect.model.ChatMessage dbMsg = com.careconnect.model.ChatMessage.builder()
                .messageType(MessageType.ASSISTANT)
                .content("Take 2 pills daily")
                .build();
        when(chatMessageRepository.findTopNByConversationOrderByCreatedAtAsc(conversation, MAX_MESSAGES))
                .thenReturn(List.of(dbMsg));

        final List<ChatMessage> result = chatMemory.messages();

        assertEquals(1, result.size());
        assertInstanceOf(AiMessage.class, result.get(0));
        assertEquals("Take 2 pills daily", ((AiMessage) result.get(0)).text());
    }

    // ========================================================================
    // cleanupOldMessages (via add())
    // ========================================================================

    @Test
    @DisplayName("cleanupOldMessages_exactlyAtLimit_noDeletion")
    void cleanupOldMessages_exactlyAtLimit_noDeletion() throws Exception {
        final UserMessage message = UserMessage.from("Hello");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        final List<com.careconnect.model.ChatMessage> allMessages = new ArrayList<>();
        for (int i = 0; i < MAX_MESSAGES; i++) {
            allMessages.add(com.careconnect.model.ChatMessage.builder()
                    .id((long) i)
                    .conversation(conversation)
                    .messageType(MessageType.USER)
                    .content("Msg " + i)
                    .build());
        }
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(allMessages);

        chatMemory.add(message);

        verify(chatMessageRepository, never()).deleteAll(anyList());
    }

    @Test
    @DisplayName("cleanupOldMessages_oneOverLimit_deletesExactlyOneOldest")
    void cleanupOldMessages_oneOverLimit_deletesExactlyOneOldest() throws Exception {
        final UserMessage message = UserMessage.from("Hello");
        when(chatMessageRepository.save(any(com.careconnect.model.ChatMessage.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        final List<com.careconnect.model.ChatMessage> allMessages = new ArrayList<>();
        for (int i = 0; i < MAX_MESSAGES + 1; i++) {
            allMessages.add(com.careconnect.model.ChatMessage.builder()
                    .id((long) i)
                    .conversation(conversation)
                    .messageType(MessageType.USER)
                    .content("Msg " + i)
                    .build());
        }
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conversation))
                .thenReturn(allMessages);

        chatMemory.add(message);

        @SuppressWarnings("unchecked") final ArgumentCaptor<List<com.careconnect.model.ChatMessage>> deleteCaptor =
                ArgumentCaptor.forClass(List.class);
        verify(chatMessageRepository).deleteAll(deleteCaptor.capture());
        assertEquals(1, deleteCaptor.getValue().size());
        assertEquals(0L, deleteCaptor.getValue().get(0).getId());
    }
}
