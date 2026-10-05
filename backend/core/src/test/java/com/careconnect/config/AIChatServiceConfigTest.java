package com.careconnect.config;

import com.careconnect.service.security.SecurityAuditService;
import dev.langchain4j.model.chat.ChatModel;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for AIChatServiceConfig.
 * <p>
 * Validates configuration bean creation behavior including validation
 * (API key, URL, HTTPS, temperature range) and ChatModel instantiation.
 * <p>
 * chatModel() calls validateConfiguration() before building the bean, so
 * missing API key / URL causes an IllegalStateException from validation.
 * The builder itself wraps any build-time exception in
 * "AI configuration failed".
 * <p>
 * Mocks SecurityAuditService to satisfy the constructor dependency.
 */
class AIChatServiceConfigTest {

    private SecurityAuditService securityAuditService;
    private AIChatServiceConfig config;

    @BeforeEach
    void setUp() throws Exception {
        // Arrange: Create mock security audit service
        securityAuditService = mock(SecurityAuditService.class);
        config = new AIChatServiceConfig(securityAuditService);
    }

    @Test
    void constructorInitializesSuccessfully() throws Exception {
        // Assert: Constructor should complete without throwing
        assertNotNull(config);
    }

    @Test
    void chatModelBeanCreatedSuccessfullyWithDeepseekProvider() throws Exception {
        // Arrange: Set valid deepseek configuration
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act: Create the ChatModel bean
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean should be created successfully
        assertNotNull(chatModel);
        verify(securityAuditService, never()).logConfigurationValidationError(anyString(), anyString(), anyString());
    }

    @Test
    void chatModelSucceedsWithOpenaiProvider() throws Exception {
        // Arrange: "openai" with valid config builds an OpenAiChatModel
        ReflectionTestUtils.setField(config, "provider", "openai");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.openai.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "gpt-4o-mini");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act: Create ChatModel — all providers use OpenAiChatModel builder
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean should be created successfully
        assertNotNull(chatModel);
    }

    @Test
    void chatModelThrowsWithEmptyApiKey() throws Exception {
        // Arrange: empty API key triggers validation failure
        ReflectionTestUtils.setField(config, "provider", "openai");
        ReflectionTestUtils.setField(config, "apiKey", "");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.openai.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "gpt-4o-mini");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act & Assert: validateConfiguration() throws for blank API key
        final IllegalStateException exception = assertThrows(IllegalStateException.class, () -> {
            config.chatModel();
        });

        assertEquals("API key is required but not configured", exception.getMessage());
        verify(securityAuditService).logConfigurationValidationError(eq("openai"), eq("API_KEY"), anyString());
    }

    @Test
    void chatModelThrowsWithNullApiKey() throws Exception {
        // Arrange: null API key triggers validation failure
        ReflectionTestUtils.setField(config, "provider", "openai");
        ReflectionTestUtils.setField(config, "apiKey", null);
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.openai.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "gpt-4o-mini");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act & Assert: validateConfiguration() throws for null API key
        final IllegalStateException exception = assertThrows(IllegalStateException.class, () -> {
            config.chatModel();
        });

        assertEquals("API key is required but not configured", exception.getMessage());
    }

    @Test
    void chatModelThrowsWithEmptyApiUrl() throws Exception {
        // Arrange: valid API key but empty URL triggers validation failure
        ReflectionTestUtils.setField(config, "provider", "openai");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "");
        ReflectionTestUtils.setField(config, "modelName", "gpt-4o-mini");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act & Assert: validateConfiguration() throws for blank URL
        final IllegalStateException exception = assertThrows(IllegalStateException.class, () -> {
            config.chatModel();
        });

        assertEquals("API URL is required but not configured", exception.getMessage());
        verify(securityAuditService).logConfigurationValidationError(eq("openai"), eq("API_URL"), anyString());
    }

    @Test
    void chatModelThrowsWithNullApiUrl() throws Exception {
        // Arrange: valid API key but null URL triggers validation failure
        ReflectionTestUtils.setField(config, "provider", "openai");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", null);
        ReflectionTestUtils.setField(config, "modelName", "gpt-4o-mini");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act & Assert: validateConfiguration() throws for null URL
        final IllegalStateException exception = assertThrows(IllegalStateException.class, () -> {
            config.chatModel();
        });

        assertEquals("API URL is required but not configured", exception.getMessage());
    }

    @Test
    void chatModelCreatesDeepseekWithHttpUrl() throws Exception {
        // Arrange: HTTP URL triggers a warning via securityAuditService but does not throw
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "http://api.example.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act: Create ChatModel — HTTP URL is warned but allowed
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean created; audit service is called with a security warning
        assertNotNull(chatModel);
        verify(securityAuditService).logConfigurationValidationError(
                eq("deepseek"), eq("API_URL_SECURITY"), anyString());
    }

    @Test
    void chatModelSucceedsWithDeepseekShortApiKey() throws Exception {
        // Arrange: Short API key (< 20 chars) triggers a warning but does not throw
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "short-key-123");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act: Create ChatModel - should succeed
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel);
    }

    @Test
    void chatModelSucceedsWithDeepseekNegativeTemperature() throws Exception {
        // Arrange: Negative temperature triggers a warning but does not throw
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", -0.5);

        // Act: Create ChatModel - should succeed
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel);
    }

    @Test
    void chatModelSucceedsWithDeepseekHighTemperature() throws Exception {
        // Arrange: Temperature above 2.0 triggers a warning but does not throw
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", 2.5);

        // Act: Create ChatModel - should succeed
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel);
    }

    @Test
    void chatModelSucceedsWithDeepseekCaseInsensitive() throws Exception {
        // Arrange: Set configuration with "DeepSeek" (mixed case)
        ReflectionTestUtils.setField(config, "provider", "DeepSeek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-deepseek-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", 0.7);

        // Act: Create ChatModel
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel);
        verify(securityAuditService, never()).logConfigurationValidationError(anyString(), anyString(), anyString());
    }

    @Test
    void chatModelSucceedsWithDeepseekTemperatureBoundaries() throws Exception {
        // Arrange: Test lower boundary (0.0)
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");
        ReflectionTestUtils.setField(config, "temperature", 0.0);

        // Act: Create ChatModel with temperature 0.0
        final ChatModel chatModel1 = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel1);

        // Arrange: Test upper boundary (2.0)
        ReflectionTestUtils.setField(config, "temperature", 2.0);

        // Act: Create ChatModel with temperature 2.0
        final ChatModel chatModel2 = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel2);
    }

    @Test
    void chatModelSucceedsWithDeepseekTypicalTemperatureValues() throws Exception {
        // Arrange: Test common temperature values (0.5, 0.7, 1.0, 1.5)
        ReflectionTestUtils.setField(config, "provider", "deepseek");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.deepseek.com/v1");
        ReflectionTestUtils.setField(config, "modelName", "deepseek-chat");

        final double[] temperatures = {0.5, 0.7, 1.0, 1.5};

        for (final double temp : temperatures) {
            // Arrange: Set temperature
            ReflectionTestUtils.setField(config, "temperature", temp);

            // Act: Create ChatModel
            final ChatModel chatModel = config.chatModel();

            // Assert: Bean created successfully
            assertNotNull(chatModel, "ChatModel should be created with temperature " + temp);
        }
    }

    @Test
    void chatModelSucceedsWithMistralProvider() throws Exception {
        // Arrange: All providers use the same OpenAiChatModel builder, so
        // "mistral" with valid config should succeed just like deepseek.
        ReflectionTestUtils.setField(config, "provider", "mistral");
        ReflectionTestUtils.setField(config, "apiKey", "sk-test-1234567890abcdefghijklmnopqrstuvwxyz");
        ReflectionTestUtils.setField(config, "apiUrl", "https://api.mistral.ai/v1");
        ReflectionTestUtils.setField(config, "modelName", "mistral-medium");
        ReflectionTestUtils.setField(config, "temperature", 1.0);

        // Act: Create ChatModel
        final ChatModel chatModel = config.chatModel();

        // Assert: Bean created successfully
        assertNotNull(chatModel);
        verify(securityAuditService, never()).logConfigurationValidationError(
                anyString(), anyString(), anyString());
    }
}
