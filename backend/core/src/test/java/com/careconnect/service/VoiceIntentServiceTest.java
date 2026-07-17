package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.VoiceIntentRequest;
import com.careconnect.dto.VoiceIntentResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class VoiceIntentServiceTest {

    private AIServiceFactory mockFactory;
    private AIService mockAIService;
    private VoiceIntentService service;

    @BeforeEach
    void setUp() {
        mockFactory = mock(AIServiceFactory.class);
        mockAIService = mock(AIService.class);
        when(mockFactory.getService()).thenReturn(mockAIService);
        service = new VoiceIntentService(mockFactory, new ObjectMapper());
    }

    @Test
    @DisplayName("navigate intent parsed correctly from AI response")
    void extractIntent_navigate_parsesCorrectly() {
        String aiJson = "{\"intent\":\"navigate\",\"entities\":{\"destination\":\"calendar\"},\"confidence\":0.95}";
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(aiJson);
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("take me to the calendar")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("navigate");
        assertThat(response.getDestination()).isEqualTo("/calendar");
        assertThat(response.getConfidence()).isEqualTo(0.95);
        assertThat(response.isSuccess()).isTrue();
        assertThat(response.isRequiresConfirmation()).isTrue();
    }

    @Test
    @DisplayName("call intent extracts target entity")
    void extractIntent_call_extractsTarget() {
        String aiJson = "{\"intent\":\"call\",\"entities\":{\"target\":\"Dr. Smith\"},\"confidence\":0.88}";
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(aiJson);
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("call Dr. Smith")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("call");
        assertThat(response.getEntities()).containsEntry("target", "Dr. Smith");
        assertThat(response.getConfidence()).isEqualTo(0.88);
        assertThat(response.isSuccess()).isTrue();
        assertThat(response.isRequiresConfirmation()).isTrue();
        assertThat(response.getDisplayLabel()).isEqualTo("Call Dr. Smith");
    }

    @Test
    @DisplayName("schedule intent extracts target and date")
    void extractIntent_schedule_extractsEntities() {
        String aiJson = "{\"intent\":\"schedule\",\"entities\":{\"target\":\"Dr. Jones\",\"date\":\"Tuesday\"},\"confidence\":0.82}";
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(aiJson);
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("schedule an appointment with Dr. Jones on Tuesday")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("schedule");
        assertThat(response.getEntities()).containsEntry("target", "Dr. Jones");
        assertThat(response.getEntities()).containsEntry("date", "Tuesday");
        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getDisplayLabel()).isEqualTo("Schedule with Dr. Jones");
    }

    @Test
    @DisplayName("malformed AI response returns unknown intent")
    void extractIntent_malformedResponse_returnsUnknown() {
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse("I'm sorry, I don't understand that command.");
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("do something weird")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("unknown");
        assertThat(response.isSuccess()).isFalse();
    }

    @Test
    @DisplayName("null AI response returns unknown intent")
    void extractIntent_nullResponse_returnsUnknown() {
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(null);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("hello")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("unknown");
        assertThat(response.isSuccess()).isFalse();
    }

    @Test
    @DisplayName("AI exception returns error response")
    void extractIntent_exception_returnsError() {
        when(mockAIService.processChat(any(ChatRequest.class)))
                .thenThrow(new RuntimeException("Bedrock unavailable"));

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("take me home")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("unknown");
        assertThat(response.isSuccess()).isFalse();
        assertThat(response.getErrorMessage()).isEqualTo("Bedrock unavailable");
    }

    @Test
    @DisplayName("JSON wrapped in markdown code block is parsed correctly")
    void extractIntent_markdownWrapped_parsesCorrectly() {
        String aiJson = "```json\n{\"intent\":\"navigate\",\"entities\":{\"destination\":\"home\"},\"confidence\":0.9}\n```";
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(aiJson);
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("go home")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("navigate");
        assertThat(response.getDestination()).isEqualTo("/dashboard");
        assertThat(response.isSuccess()).isTrue();
    }

    @Test
    @DisplayName("unknown destination returns success false for navigate")
    void extractIntent_unknownDestination_returnsFailure() {
        String aiJson = "{\"intent\":\"navigate\",\"entities\":{\"destination\":\"settings\"},\"confidence\":0.7}";
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(aiJson);
        when(mockAIService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance("take me to settings")
                .locale("en")
                .build();

        VoiceIntentResponse response = service.extractIntent(request);

        assertThat(response.getIntent()).isEqualTo("navigate");
        assertThat(response.getDestination()).isNull();
        assertThat(response.isSuccess()).isFalse();
    }
}
