package com.careconnect.config;

import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link AiProperties} and its nested {@link AiProperties.ProviderProps} class.
 * <p>
 * AiProperties is a Spring {@code @ConfigurationProperties} bean that holds per-provider
 * AI settings (API key, model name, base URL, temperature, max tokens). These tests verify
 * default values, setter/getter correctness, null tolerance, and multi-provider support
 * without needing a Spring context — plain Java instantiation is sufficient because the
 * class is a simple POJO with no dependencies.
 */
class AiPropertiesTest {

    @Test
    void providerProps_DefaultValuesAreCorrect() throws Exception {
        // Verifies that ProviderProps ships with safe defaults so callers can rely on
        // temperature (0.2) and maxTokens (1500) even when no explicit values are bound,
        // while optional string fields start as null so missing config is detectable.
        final AiProperties.ProviderProps props = new AiProperties.ProviderProps();

        assertEquals(0.2, props.getTemperature());
        assertEquals(1500, props.getMaxTokens());
        assertNull(props.getApiKey());
        assertNull(props.getModel());
        assertNull(props.getBaseUrl());
    }

    @Test
    void providerProps_SettersAndGettersWorkCorrectly() throws Exception {
        // Verifies that all five setters store values that are then returned by the
        // corresponding getters — a basic contract check for the POJO's data binding.
        final AiProperties.ProviderProps props = new AiProperties.ProviderProps();

        props.setApiKey("test-key");
        props.setModel("gpt-4");
        props.setBaseUrl("https://api.openai.com");
        props.setTemperature(0.7);
        props.setMaxTokens(2000);

        assertEquals("test-key", props.getApiKey());
        assertEquals("gpt-4", props.getModel());
        assertEquals("https://api.openai.com", props.getBaseUrl());
        assertEquals(0.7, props.getTemperature());
        assertEquals(2000, props.getMaxTokens());
    }

    @Test
    void providerProps_AllowsNullValuesForOptionalFields() throws Exception {
        // Confirms that all fields accept null, which is required so that absent YAML
        // properties do not cause a NullPointerException during Spring binding.
        final AiProperties.ProviderProps props = new AiProperties.ProviderProps();

        props.setApiKey(null);
        props.setModel(null);
        props.setBaseUrl(null);
        props.setTemperature(null);
        props.setMaxTokens(null);

        assertNull(props.getApiKey());
        assertNull(props.getModel());
        assertNull(props.getBaseUrl());
        assertNull(props.getTemperature());
        assertNull(props.getMaxTokens());
    }

    @Test
    void aiProperties_ProvidersMapCanBeSetAndRetrieved() throws Exception {
        // Verifies that AiProperties stores a providers map keyed by provider name
        // (e.g. "openai") and that entries retain the values they were populated with.
        // This mirrors how Spring binds a YAML block like `ai.providers.openai.*`.
        final AiProperties properties = new AiProperties();

        final AiProperties.ProviderProps openAiProps = new AiProperties.ProviderProps();
        openAiProps.setApiKey("openai-key");
        openAiProps.setModel("gpt-4");

        final Map<String, AiProperties.ProviderProps> providers = new HashMap<>();
        providers.put("openai", openAiProps);

        properties.setProviders(providers);

        assertNotNull(properties.getProviders());
        assertEquals(1, properties.getProviders().size());
        assertEquals("openai-key",
                properties.getProviders().get("openai").getApiKey());
        assertEquals("gpt-4",
                properties.getProviders().get("openai").getModel());
    }

    @Test
    void aiProperties_ProvidersMapCanBeNull() throws Exception {
        // Ensures the class does not enforce a non-null providers map, allowing the
        // application to start even when no AI provider section is present in config.
        final AiProperties properties = new AiProperties();

        properties.setProviders(null);

        assertNull(properties.getProviders());
    }

    @Test
    void aiProperties_SupportsMultipleProviders() throws Exception {
        // Confirms that multiple providers (e.g. OpenAI and DeepSeek) can coexist in
        // the same map and are independently retrievable by their provider-name key.
        final AiProperties properties = new AiProperties();

        final AiProperties.ProviderProps openAi = new AiProperties.ProviderProps();
        openAi.setApiKey("openai-key");

        final AiProperties.ProviderProps deepSeek = new AiProperties.ProviderProps();
        deepSeek.setApiKey("deepseek-key");

        final Map<String, AiProperties.ProviderProps> providers = new HashMap<>();
        providers.put("openai", openAi);
        providers.put("deepseek", deepSeek);

        properties.setProviders(providers);

        assertEquals(2, properties.getProviders().size());
        assertEquals("openai-key",
                properties.getProviders().get("openai").getApiKey());
        assertEquals("deepseek-key",
                properties.getProviders().get("deepseek").getApiKey());
    }
}
