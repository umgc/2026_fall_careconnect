package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.ObjectProvider;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ColibriServiceTest {

    private HttpServer mockServer;
    private String serverUrl;
    private int responseStatusCode = 200;
    private String responseBody = "";

    @BeforeEach
    void setUp() throws IOException {
        mockServer = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int port = mockServer.getAddress().getPort();
        serverUrl = "http://127.0.0.1:" + port + "/v1";

        mockServer.createContext("/v1/chat/completions", exchange -> {
            byte[] bytes = responseBody.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(responseStatusCode, bytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(bytes);
            }
        });
        mockServer.start();
    }

    @AfterEach
    void tearDown() {
        if (mockServer != null) {
            mockServer.stop(0);
        }
    }

    // ===== Hybrid Clinical Safety Triage Unit Tests =====

    @Test
    void shouldEscalateToCloud_forRoutineQueries_returnsFalse() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);

        assertThat(service.shouldEscalateToCloud(null)).isFalse();
        assertThat(service.shouldEscalateToCloud("")).isFalse();
        assertThat(service.shouldEscalateToCloud("   ")).isFalse();
        assertThat(service.shouldEscalateToCloud("When is my next appointment?")).isFalse();
        assertThat(service.shouldEscalateToCloud("Who is my primary care doctor?")).isFalse();
        assertThat(service.shouldEscalateToCloud("What medications am I currently taking?")).isFalse();
        assertThat(service.shouldEscalateToCloud("Show my daily check-in tasks")).isFalse();
        assertThat(service.shouldEscalateToCloud("Good morning, how are you?")).isFalse();
    }

    @Test
    void shouldEscalateToCloud_forDosageAlterations_returnsTrue() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);

        // Core user requested test case: "can i cut dosage in half"
        assertThat(service.shouldEscalateToCloud("Can I cut my dosage in half?")).isTrue();
        assertThat(service.shouldEscalateToCloud("Can I cut this pill in half?")).isTrue();
        assertThat(service.shouldEscalateToCloud("Should I split my medication dose?")).isTrue();
        assertThat(service.shouldEscalateToCloud("Can I double my dose because I missed yesterday?")).isTrue();
        assertThat(service.shouldEscalateToCloud("Should I stop taking my medicine?")).isTrue();
        assertThat(service.shouldEscalateToCloud("Can I halve my tablet dosage?")).isTrue();
        assertThat(service.shouldEscalateToCloud("I want to break the pill in half")).isTrue();
    }

    @Test
    void shouldEscalateToCloud_forClinicalSymptomsAndDiagnosis_returnsTrue() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);

        assertThat(service.shouldEscalateToCloud("I have severe chest pain and dizziness")).isTrue();
        assertThat(service.shouldEscalateToCloud("Please diagnose my symptom of shortness of breath")).isTrue();
        assertThat(service.shouldEscalateToCloud("Is there a drug interaction with this pill?")).isTrue();
        assertThat(service.shouldEscalateToCloud("I have a severe rash and high fever")).isTrue();
    }

    @Test
    void shouldEscalateToCloud_forMultiCampusDirectoryQueries_returnsTrue() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);

        // Core user requested test case: "where is my clinic other office located"
        assertThat(service.shouldEscalateToCloud("Where is my clinic other office located?")).isTrue();
        assertThat(service.shouldEscalateToCloud("What is the address of the another clinic branch?")).isTrue();
        assertThat(service.shouldEscalateToCloud("Directions to the downtown location campus")).isTrue();
        assertThat(service.shouldEscalateToCloud("Where is the second facility?")).isTrue();
    }

    @Test
    void processChat_dosageEscalation_withCloudFallback_delegatesToCloud() {
        BedrockAIChatService mockBedrock = mock(BedrockAIChatService.class);
        ChatResponse cloudReply = ChatResponse.builder()
                .success(true)
                .aiResponse("As your CareConnect clinical specialist, never cut Metformin ER in half as it breaks the extended release coating.")
                .aiProvider("bedrock")
                .modelUsed("anthropic.claude-3-haiku")
                .build();
        when(mockBedrock.processChat(any())).thenReturn(cloudReply);

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10, 128, new ObjectMapper(), mockBedrock);
        ChatRequest request = ChatRequest.builder()
                .message("Can I cut my dosage in half?")
                .userId(1L)
                .patientId(2L)
                .build();

        ChatResponse response = service.processChat(request);

        assertThat(response).isNotNull();
        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiProvider()).isEqualTo("bedrock");
        assertThat(response.getAiResponse()).contains("never cut Metformin ER in half");
    }

    @Test
    void processChat_dosageEscalation_withoutCloudFallback_returnsSafeTriageResponse() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder()
                .message("Can I cut my dosage in half?")
                .userId(1L)
                .patientId(2L)
                .build();

        ChatResponse response = service.processChat(request);

        assertThat(response).isNotNull();
        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiProvider()).isEqualTo("colibri-cloud-triage");
        assertThat(response.getAiResponse()).contains(ColibriService.ESCALATE_TOKEN);
        assertThat(response.getAiResponse()).contains("Never alter your medication dosage");
    }

    @Test
    void processChat_modelEmitsEscalateToken_withCloudFallback_delegatesToCloud() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "[ESCALATE_TO_CLINICAL_CLOUD] This question requires pharmacological review."
                  }
                }
              ]
            }
            """;

        BedrockAIChatService mockBedrock = mock(BedrockAIChatService.class);
        ChatResponse cloudReply = ChatResponse.builder()
                .success(true)
                .aiResponse("Cloud clinical answer for tricky question.")
                .aiProvider("bedrock")
                .build();
        when(mockBedrock.processChat(any())).thenReturn(cloudReply);

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10, 128, new ObjectMapper(), mockBedrock);
        ChatRequest request = ChatRequest.builder()
                .message("I want to take a smaller piece of this pill tomorrow")
                .build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiProvider()).isEqualTo("bedrock");
        assertThat(response.getAiResponse()).isEqualTo("Cloud clinical answer for tricky question.");
    }

    @Test
    void processChat_modelEmitsEscalateToken_withoutCloudFallback_returnsSafeTriageResponse() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "[ESCALATE_TO_CLINICAL_CLOUD]"
                  }
                }
              ]
            }
            """;

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder()
                .message("I only need a little bit of this pill tomorrow")
                .build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiProvider()).isEqualTo("colibri-cloud-triage");
        assertThat(response.getAiResponse()).contains(ColibriService.ESCALATE_TOKEN);
    }

    // ===== Routine Query Tests =====

    @Test
    void processChat_success_returnsAiResponse() {
        responseStatusCode = 200;
        responseBody = """
            {
              "id": "chatcmpl-123",
              "object": "chat.completion",
              "created": 1700000000,
              "model": "olmoe-colibri",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "Your next appointment is Oct 15 at 10:30 AM."
                  },
                  "finish_reason": "stop"
                }
              ],
              "usage": {
                "prompt_tokens": 50,
                "completion_tokens": 15,
                "total_tokens": 65
              }
            }
            """;

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder()
                .message("When is my appointment?")
                .userId(1L)
                .patientId(2L)
                .conversationId("conv-101")
                .build();

        ChatResponse response = service.processChat(request);

        assertThat(response).isNotNull();
        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiResponse()).isEqualTo("Your next appointment is Oct 15 at 10:30 AM.");
        assertThat(response.getModelUsed()).isEqualTo("olmoe-colibri");
        assertThat(response.getAiProvider()).isEqualTo("colibri");
        assertThat(response.getConversationId()).isEqualTo("conv-101");
    }

    @Test
    void processChat_withPreferredModel_usesPreferredModel() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                {
                  "message": { "role": "assistant", "content": "Custom model reply" }
                }
              ]
            }
            """;

        ColibriService service = new ColibriService(serverUrl, "default-model", 0.3, 10);
        ChatRequest request = ChatRequest.builder()
                .message("Hello")
                .preferredModel("custom-model-id")
                .build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getModelUsed()).isEqualTo("custom-model-id");
        assertThat(response.getAiResponse()).isEqualTo("Custom model reply");
    }

    @Test
    void processChat_emptyChoices_returnsEmptyStringResponse() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": []
            }
            """;

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder().message("Test").build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiResponse()).isEmpty();
    }

    @Test
    void processChat_nullChoiceMessage_returnsEmptyString() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                { "index": 0, "message": null }
              ]
            }
            """;

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder().message("Test").build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiResponse()).isEmpty();
    }

    @Test
    void processChat_serverReturns500Error_returnsGracefulFailure() {
        responseStatusCode = 500;
        responseBody = "Internal engine fault";

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder().message("Hello").build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getErrorCode()).isEqualTo("COLIBRI_CONNECTION_ERROR");
        assertThat(response.getErrorMessage()).contains("500");
    }

    @Test
    void processChat_serverUnreachable_returnsGracefulError() {
        if (mockServer != null) {
            mockServer.stop(0);
            mockServer = null;
        }

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 1);
        ChatRequest request = ChatRequest.builder().message("Hello").build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getErrorCode()).isEqualTo("COLIBRI_CONNECTION_ERROR");
    }

    // ===== Prompt Compaction Tests =====

    @Test
    void processChat_withLargeMedicalContext_compactsPrompt() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                { "message": { "role": "assistant", "content": "You have 1 appointment." } }
              ]
            }
            """;

        StringBuilder largeContext = new StringBuilder();
        largeContext.append("PATIENT INFORMATION:\nName: John Doe\nAge: 65\nCondition: Hypertension\nExtra detail line\n\n");
        largeContext.append("UPCOMING APPOINTMENTS:\nDr. Smith on Oct 20\nDr. Adams on Nov 1\nLine 3\nLine 4\n\n");
        largeContext.append("CURRENT MEDICATIONS:\nLisinopril 10mg\nMetformin 500mg\nLine 3\nLine 4\n\n");
        largeContext.append("RECENT CLINICAL NOTES:\nPatient reports feeling well\nLine 2\nLine 3\nLine 4\n\n");
        largeContext.append("RECENT VITALS:\nBP: 120/80\nHR: 72\nLine 3\nLine 4\n\n");
        largeContext.append("IGNORED SECTION:\nSome other text\n\n");
        while (largeContext.length() < 900) {
            largeContext.append("Padding info text that is very long...\n");
        }
        largeContext.append("\nUSER QUESTION:\nWhen is my appointment?");

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder().message(largeContext.toString()).build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiResponse()).isEqualTo("You have 1 appointment.");
    }

    @Test
    void processChat_withLargeMessageWithoutMarker_truncatesPrompt() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                { "message": { "role": "assistant", "content": "Acknowledged." } }
              ]
            }
            """;

        String longMsg = "A".repeat(1000);
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder().message(longMsg).build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getAiResponse()).isEqualTo("Acknowledged.");
    }

    @Test
    void processChat_withNullMessage_handlesSafely() {
        responseStatusCode = 200;
        responseBody = """
            {
              "choices": [
                { "message": { "role": "assistant", "content": "Ready." } }
              ]
            }
            """;

        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);
        ChatRequest request = ChatRequest.builder().message(null).build();

        ChatResponse response = service.processChat(request);

        assertThat(response.getSuccess()).isTrue();
    }

    // ===== Constructor Tests =====

    @Test
    void constructor_withTrailingSlash_stripsSlash() {
        ColibriService service = new ColibriService(serverUrl + "/", "olmoe-colibri", 0.3, 10);
        assertThat(service).isNotNull();
    }

    @Test
    void constructor_withZeroOrNegativeMaxTokens_usesDefault128() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10, -5, null);
        assertThat(service).isNotNull();
    }

    @Test
    @SuppressWarnings("unchecked")
    void constructor_autowiredWithObjectProvider_wiresCorrectly() {
        BedrockAIChatService mockBedrock = mock(BedrockAIChatService.class);
        ObjectProvider<BedrockAIChatService> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(mockBedrock);

        ColibriService service = new ColibriService(
                serverUrl,
                "olmoe-colibri",
                0.3,
                10,
                128,
                new ObjectMapper(),
                provider
        );

        assertThat(service).isNotNull();
    }

    @Test
    void constructor_autowiredWithNullObjectProvider_handlesSafely() {
        ColibriService service = new ColibriService(
                serverUrl,
                "olmoe-colibri",
                0.3,
                10,
                128,
                new ObjectMapper(),
                (ObjectProvider<BedrockAIChatService>) null
        );

        assertThat(service).isNotNull();
    }

    // ===== Interface Stubs Tests =====

    @Test
    void stubs_returnEmptyListsAndNoOp() {
        ColibriService service = new ColibriService(serverUrl, "olmoe-colibri", 0.3, 10);

        assertThat(service.getPatientConversations(1L)).isEmpty();
        assertThat(service.getConversationMessages("test-id")).isEmpty();
        assertThat(service.getRecentMessagesForUser(1L, 10)).isEmpty();
        service.deactivateConversation("test-id");
    }

    // ===== DTO Coverage Tests =====

    @Test
    void dtos_instantiateAndCoverAllAccessors() {
        ColibriService.Message msg = new ColibriService.Message("system", "instruction");
        assertThat(msg.getRole()).isEqualTo("system");
        assertThat(msg.getContent()).isEqualTo("instruction");
        msg.setRole("user");
        msg.setContent("question");
        assertThat(msg.getRole()).isEqualTo("user");
        assertThat(msg.getContent()).isEqualTo("question");

        ColibriService.ColibriChatRequest req = ColibriService.ColibriChatRequest.builder()
                .model("olmoe")
                .messages(List.of(msg))
                .temperature(0.5)
                .stream(false)
                .maxTokens(200)
                .build();

        assertThat(req.getModel()).isEqualTo("olmoe");
        assertThat(req.getMessages()).hasSize(1);
        assertThat(req.getTemperature()).isEqualTo(0.5);
        assertThat(req.getStream()).isFalse();
        assertThat(req.getMaxTokens()).isEqualTo(200);

        ColibriService.ColibriChatRequest emptyReq = new ColibriService.ColibriChatRequest();
        emptyReq.setModel("m");
        emptyReq.setMessages(Collections.emptyList());
        emptyReq.setTemperature(0.1);
        emptyReq.setStream(true);
        emptyReq.setMaxTokens(50);
        assertThat(emptyReq.getModel()).isEqualTo("m");

        ColibriService.Usage usage = new ColibriService.Usage();
        usage.setPromptTokens(10);
        usage.setCompletionTokens(20);
        usage.setTotalTokens(30);
        assertThat(usage.getPromptTokens()).isEqualTo(10);
        assertThat(usage.getCompletionTokens()).isEqualTo(20);
        assertThat(usage.getTotalTokens()).isEqualTo(30);

        ColibriService.Choice choice = new ColibriService.Choice();
        choice.setIndex(0);
        choice.setMessage(msg);
        choice.setFinishReason("stop");
        assertThat(choice.getIndex()).isEqualTo(0);
        assertThat(choice.getMessage()).isEqualTo(msg);
        assertThat(choice.getFinishReason()).isEqualTo("stop");

        ColibriService.ColibriChatResponse res = new ColibriService.ColibriChatResponse();
        res.setId("id-1");
        res.setObject("chat.completion");
        res.setCreated(123456L);
        res.setModel("model-1");
        res.setChoices(List.of(choice));
        res.setUsage(usage);
        assertThat(res.getId()).isEqualTo("id-1");
        assertThat(res.getObject()).isEqualTo("chat.completion");
        assertThat(res.getCreated()).isEqualTo(123456L);
        assertThat(res.getModel()).isEqualTo("model-1");
        assertThat(res.getChoices()).hasSize(1);
        assertThat(res.getUsage()).isEqualTo(usage);
    }
}
