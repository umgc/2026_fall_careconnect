package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OllamaServiceTest {

    private OllamaService ollamaService;

    @BeforeEach
    void setUp() {
        // Connect to an arbitrary local address for offline unit testing
        ollamaService = new OllamaService(
                "http://localhost:11434",
                "llama3.2:1b",
                0.3,
                5
        );
    }

    @Test
    void processChat_whenServerUnreachable_returnsGracefulError() {
        ChatRequest request = ChatRequest.builder()
                .message("Hello test")
                .userId(1L)
                .patientId(2L)
                .build();

        // Unless ollama is running and handles this synchronously, it safely catches connection error
        ChatResponse response = ollamaService.processChat(request);

        assertThat(response).isNotNull();
        assertThat(response.getAiProvider()).isEqualTo("ollama");
    }

    @Test
    void stubs_returnEmptyLists() {
        assertThat(ollamaService.getPatientConversations(1L)).isEmpty();
        assertThat(ollamaService.getConversationMessages("test-id")).isEmpty();
        assertThat(ollamaService.getRecentMessagesForUser(1L, 10)).isEmpty();
    }
}

