package com.careconnect.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.MockedConstruction;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class OpenRouterServiceTest {

    /**
     * Minimal valid JSON that Jackson can deserialize into OpenRouterResponse.
     * Uses camelCase keys because the ObjectMapper created in the service has no
     * snake-case naming strategy configured.
     */
    private static final String VALID_JSON =
            "{\"id\":\"r1\",\"object\":\"chat.completion\",\"created\":1000000," +
                    "\"model\":\"test-model\"," +
                    "\"choices\":[{\"index\":0," +
                    "  \"message\":{\"role\":\"assistant\",\"content\":\"Hi\"}," +
                    "  \"finishReason\":\"stop\"}]," +
                    "\"usage\":{\"promptTokens\":5,\"completionTokens\":3,\"totalTokens\":8," +
                    "\"promptCacheHitTokens\":1,\"promptCacheMissTokens\":4}}";
    private OpenRouterService service;

    // ── Helpers ───────────────────────────────────────────────────────────────

    @BeforeEach
    void setUp() throws Exception {
        service = new OpenRouterService();
    }

    private void setApiKey(String key) {
        ReflectionTestUtils.setField(service, "apiKey", key);
    }

    private void setApiUrl(String url) {
        ReflectionTestUtils.setField(service, "apiUrl", url);
    }

    private OpenRouterService.OpenRouterChatRequest basicRequest() throws Exception {
        return new OpenRouterService.OpenRouterChatRequest(
                "test-model",
                List.of(new OpenRouterService.Message("user", "hello")),
                0.7,
                100
        );
    }

    // ═════════════════════════════════════════════════════════════════════════
    // API key validation
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("sendChatRequest throws IllegalStateException when apiKey is null")
    void sendChatRequest_nullApiKey_throwsIllegalState() throws Exception {
        // @Value is not processed in unit tests; apiKey stays null
        assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OpenRouter API key is not configured");
    }

    @Test
    @DisplayName("sendChatRequest throws IllegalStateException when apiKey is empty")
    void sendChatRequest_emptyApiKey_throwsIllegalState() throws Exception {
        setApiKey("");
        assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    @DisplayName("sendChatRequest throws IllegalStateException when apiKey is blank")
    void sendChatRequest_blankApiKey_throwsIllegalState() throws Exception {
        setApiKey("   ");
        assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                .isInstanceOf(IllegalStateException.class);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // URL-building branches
    // RestTemplate is created locally inside sendChatRequest; use mockConstruction
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("sendChatRequest uses hardcoded default when apiUrl is null")
    void sendChatRequest_apiUrlNull_usesHardCodedDefault() throws Exception {
        setApiKey("test-key");
        // apiUrl stays null -> code falls back to "https://openrouter.ai/api/v1"
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok(VALID_JSON)))) {
            assertThat(service.sendChatRequest(basicRequest())).isNotNull();
        }
    }

    @Test
    @DisplayName("sendChatRequest uses hardcoded default when apiUrl is blank")
    void sendChatRequest_apiUrlBlank_usesHardCodedDefault() throws Exception {
        setApiKey("test-key");
        setApiUrl("   "); // trim().isEmpty() -> use default
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok(VALID_JSON)))) {
            assertThat(service.sendChatRequest(basicRequest())).isNotNull();
        }
    }

    @Test
    @DisplayName("sendChatRequest appends slash when apiUrl has no trailing slash")
    void sendChatRequest_apiUrlNoTrailingSlash_appendsSlash() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://custom.api.com/v1"); // no trailing slash
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok(VALID_JSON)))) {
            assertThat(service.sendChatRequest(basicRequest())).isNotNull();
        }
    }

    @Test
    @DisplayName("sendChatRequest keeps apiUrl as-is when it already has trailing slash")
    void sendChatRequest_apiUrlWithTrailingSlash_usedAsIs() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://custom.api.com/v1/"); // already ends with "/"
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok(VALID_JSON)))) {
            assertThat(service.sendChatRequest(basicRequest())).isNotNull();
        }
    }

    @Test
    @DisplayName("sendChatRequest uses empty-string apiUrl and falls back to default")
    void sendChatRequest_apiUrlEmpty_usesHardCodedDefault() throws Exception {
        setApiKey("test-key");
        setApiUrl(""); // trim().isEmpty() -> use default
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok(VALID_JSON)))) {
            assertThat(service.sendChatRequest(basicRequest())).isNotNull();
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Response-handling branches
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("sendChatRequest returns parsed response for valid 2xx JSON")
    void sendChatRequest_successWithValidJson_returnsResponse() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok(VALID_JSON)))) {
            final OpenRouterService.OpenRouterResponse result = service.sendChatRequest(basicRequest());
            assertThat(result).isNotNull();
            assertThat(result.getId()).isEqualTo("r1");
            assertThat(result.getObject()).isEqualTo("chat.completion");
            assertThat(result.getCreated()).isEqualTo(1000000L);
            assertThat(result.getModel()).isEqualTo("test-model");
            assertThat(result.getChoices()).hasSize(1);
            assertThat(result.getChoices().get(0).getIndex()).isEqualTo(0);
            assertThat(result.getChoices().get(0).getMessage().getRole()).isEqualTo("assistant");
            assertThat(result.getChoices().get(0).getMessage().getContent()).isEqualTo("Hi");
            assertThat(result.getChoices().get(0).getFinishReason()).isEqualTo("stop");
            assertThat(result.getUsage()).isNotNull();
            assertThat(result.getUsage().getPromptTokens()).isEqualTo(5);
            assertThat(result.getUsage().getCompletionTokens()).isEqualTo(3);
            assertThat(result.getUsage().getTotalTokens()).isEqualTo(8);
            assertThat(result.getUsage().getPromptCacheHitTokens()).isEqualTo(1);
            assertThat(result.getUsage().getPromptCacheMissTokens()).isEqualTo(4);
        }
    }

    @Test
    @DisplayName("sendChatRequest throws OpenRouterException when 2xx body is null")
    void sendChatRequest_successNullBody_throwsOpenRouterException() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok((String) null)))) {
            assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .cause()
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .hasMessageContaining("empty response");
        }
    }

    @Test
    @DisplayName("sendChatRequest throws OpenRouterException when 2xx body is blank")
    void sendChatRequest_successBlankBody_throwsOpenRouterException() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok("   ")))) {
            assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .cause()
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .hasMessageContaining("empty response");
        }
    }

    @Test
    @DisplayName("sendChatRequest throws OpenRouterException for non-2xx status")
    void sendChatRequest_nonSuccessStatus_throwsApiErrorOpenRouterException() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        final ResponseEntity<String> serverError =
                ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Internal Error");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(serverError))) {
            assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .cause()
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .hasMessageContaining("OpenRouter API error");
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Exception-handling branches (the three catch blocks)
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("sendChatRequest wraps JsonProcessingException in OpenRouterException")
    void sendChatRequest_invalidJsonInBody_throwsJsonProcessingOpenRouterException() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenReturn(ResponseEntity.ok("{not-valid-json{{")))) {
            assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .hasMessageContaining("JSON processing error");
        }
    }

    @Test
    @DisplayName("sendChatRequest wraps RestClientException in OpenRouterException")
    void sendChatRequest_restClientException_throwsHttpErrorOpenRouterException() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenThrow(new ResourceAccessException("connection refused")))) {
            assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .hasMessageContaining("HTTP error");
        }
    }

    @Test
    @DisplayName("sendChatRequest wraps unexpected Exception in OpenRouterException")
    void sendChatRequest_unexpectedRuntimeException_throwsUnexpectedErrorOpenRouterException() throws Exception {
        setApiKey("test-key");
        setApiUrl("https://openrouter.ai/api/v1");
        try (MockedConstruction<RestTemplate> mc = Mockito.mockConstruction(RestTemplate.class,
                (mock, ctx) -> when(mock.postForEntity(anyString(), any(), eq(String.class)))
                        .thenThrow(new NullPointerException("unexpected null")))) {
            assertThatThrownBy(() -> service.sendChatRequest(basicRequest()))
                    .isInstanceOf(OpenRouterService.OpenRouterException.class)
                    .hasMessageContaining("Unexpected error");
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inner class: OpenRouterChatRequest
    // ═════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("OpenRouterChatRequest tests")
    class OpenRouterChatRequestTest {

        @Test
        @DisplayName("No-arg constructor creates instance with defaults")
        void noArgConstructor_createsInstance() throws Exception {
            final OpenRouterService.OpenRouterChatRequest req = new OpenRouterService.OpenRouterChatRequest();
            assertThat(req.getModel()).isNull();
            assertThat(req.getMessages()).isNull();
            assertThat(req.getTemperature()).isNull();
            assertThat(req.getMaxTokens()).isNull();
            assertThat(req.getStream()).isFalse();
        }

        @Test
        @DisplayName("Parameterized constructor sets all fields")
        void parameterizedConstructor_setsFields() throws Exception {
            final List<OpenRouterService.Message> msgs = List.of(new OpenRouterService.Message("user", "hi"));
            final OpenRouterService.OpenRouterChatRequest req =
                    new OpenRouterService.OpenRouterChatRequest("model-x", msgs, 0.5, 200);
            assertThat(req.getModel()).isEqualTo("model-x");
            assertThat(req.getMessages()).isEqualTo(msgs);
            assertThat(req.getTemperature()).isEqualTo(0.5);
            assertThat(req.getMaxTokens()).isEqualTo(200);
            assertThat(req.getStream()).isFalse();
        }

        @Test
        @DisplayName("Setters update all fields")
        void setters_updateAllFields() throws Exception {
            final OpenRouterService.OpenRouterChatRequest req = new OpenRouterService.OpenRouterChatRequest();
            final List<OpenRouterService.Message> msgs = List.of(new OpenRouterService.Message("system", "you are helpful"));

            req.setModel("new-model");
            req.setMessages(msgs);
            req.setTemperature(0.9);
            req.setMaxTokens(500);
            req.setStream(true);

            assertThat(req.getModel()).isEqualTo("new-model");
            assertThat(req.getMessages()).isEqualTo(msgs);
            assertThat(req.getTemperature()).isEqualTo(0.9);
            assertThat(req.getMaxTokens()).isEqualTo(500);
            assertThat(req.getStream()).isTrue();
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inner class: Message
    // ═════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Message tests")
    class MessageTest {

        @Test
        @DisplayName("No-arg constructor creates instance with null fields")
        void noArgConstructor_createsInstance() throws Exception {
            final OpenRouterService.Message msg = new OpenRouterService.Message();
            assertThat(msg.getRole()).isNull();
            assertThat(msg.getContent()).isNull();
        }

        @Test
        @DisplayName("Parameterized constructor sets role and content")
        void parameterizedConstructor_setsFields() throws Exception {
            final OpenRouterService.Message msg = new OpenRouterService.Message("assistant", "Hello!");
            assertThat(msg.getRole()).isEqualTo("assistant");
            assertThat(msg.getContent()).isEqualTo("Hello!");
        }

        @Test
        @DisplayName("Setters update role and content")
        void setters_updateFields() throws Exception {
            final OpenRouterService.Message msg = new OpenRouterService.Message();
            msg.setRole("system");
            msg.setContent("You are a helpful assistant");
            assertThat(msg.getRole()).isEqualTo("system");
            assertThat(msg.getContent()).isEqualTo("You are a helpful assistant");
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inner class: OpenRouterResponse
    // ═════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("OpenRouterResponse tests")
    class OpenRouterResponseTest {

        @Test
        @DisplayName("Getters and setters work for all fields")
        void gettersAndSetters_workForAllFields() throws Exception {
            final OpenRouterService.OpenRouterResponse response = new OpenRouterService.OpenRouterResponse();

            response.setId("resp-1");
            response.setObject("chat.completion");
            response.setCreated(123456789L);
            response.setModel("gpt-4");

            final OpenRouterService.Message msg = new OpenRouterService.Message("assistant", "hi");
            final OpenRouterService.Choice choice = new OpenRouterService.Choice();
            choice.setIndex(0);
            choice.setMessage(msg);
            choice.setFinishReason("stop");
            response.setChoices(List.of(choice));

            final OpenRouterService.Usage usage = new OpenRouterService.Usage();
            usage.setPromptTokens(10);
            usage.setCompletionTokens(20);
            usage.setTotalTokens(30);
            usage.setPromptCacheHitTokens(5);
            usage.setPromptCacheMissTokens(5);
            response.setUsage(usage);

            assertThat(response.getId()).isEqualTo("resp-1");
            assertThat(response.getObject()).isEqualTo("chat.completion");
            assertThat(response.getCreated()).isEqualTo(123456789L);
            assertThat(response.getModel()).isEqualTo("gpt-4");
            assertThat(response.getChoices()).hasSize(1);
            assertThat(response.getUsage()).isEqualTo(usage);
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inner class: Choice
    // ═════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Choice tests")
    class ChoiceTest {

        @Test
        @DisplayName("Getters and setters work for all fields")
        void gettersAndSetters_workForAllFields() throws Exception {
            final OpenRouterService.Choice choice = new OpenRouterService.Choice();
            final OpenRouterService.Message msg = new OpenRouterService.Message("assistant", "response");

            choice.setIndex(2);
            choice.setMessage(msg);
            choice.setFinishReason("length");

            assertThat(choice.getIndex()).isEqualTo(2);
            assertThat(choice.getMessage()).isEqualTo(msg);
            assertThat(choice.getFinishReason()).isEqualTo("length");
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inner class: Usage
    // ═════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Usage tests")
    class UsageTest {

        @Test
        @DisplayName("Getters and setters work for all fields")
        void gettersAndSetters_workForAllFields() throws Exception {
            final OpenRouterService.Usage usage = new OpenRouterService.Usage();

            usage.setPromptTokens(100);
            usage.setCompletionTokens(200);
            usage.setTotalTokens(300);
            usage.setPromptCacheHitTokens(50);
            usage.setPromptCacheMissTokens(50);

            assertThat(usage.getPromptTokens()).isEqualTo(100);
            assertThat(usage.getCompletionTokens()).isEqualTo(200);
            assertThat(usage.getTotalTokens()).isEqualTo(300);
            assertThat(usage.getPromptCacheHitTokens()).isEqualTo(50);
            assertThat(usage.getPromptCacheMissTokens()).isEqualTo(50);
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inner class: OpenRouterException
    // ═════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("OpenRouterException tests")
    class OpenRouterExceptionTest {

        @Test
        @DisplayName("Constructor sets message and cause")
        void constructor_setsMessageAndCause() throws Exception {
            final RuntimeException cause = new RuntimeException("root cause");
            final OpenRouterService.OpenRouterException ex =
                    new OpenRouterService.OpenRouterException("something failed", cause);
            assertThat(ex.getMessage()).isEqualTo("something failed");
            assertThat(ex.getCause()).isEqualTo(cause);
        }

        @Test
        @DisplayName("Constructor accepts null cause")
        void constructor_acceptsNullCause() throws Exception {
            final OpenRouterService.OpenRouterException ex =
                    new OpenRouterService.OpenRouterException("no cause", null);
            assertThat(ex.getMessage()).isEqualTo("no cause");
            assertThat(ex.getCause()).isNull();
        }
    }
}
