package com.careconnect.model;

import com.careconnect.model.UserAIConfig.AIProvider;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class UserAIConfigTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final UserAIConfig config = new UserAIConfig();

        assertThat(config).isNotNull();
        assertThat(config.getId()).isNull();
        assertThat(config.getPatientId()).isNull();
        assertThat(config.getUserId()).isNull();
        assertThat(config.getPreferredAiProvider()).isNull();
        assertThat(config.getOpenaiModel()).isNull();
        assertThat(config.getDeepseekModel()).isNull();
        assertThat(config.getMaxTokens()).isNull();
        assertThat(config.getTemperature()).isNull();
        assertThat(config.getIsActive()).isNull();
    }

    // ─── Builder all fields ───────────────────────────────────────────────────

    @Test
    void builder_allFields() throws Exception {
        final UserAIConfig config = UserAIConfig.builder()
                .id(1L)
                .patientId(10L)
                .userId(5L)
                .preferredAiProvider(AIProvider.OPENAI)
                .openaiModel("gpt-4")
                .deepseekModel("deepseek-chat")
                .maxTokens(2048)
                .temperature(0.7)
                .conversationHistoryLimit(10)
                .systemPrompt("You are a helpful medical assistant.")
                .includeVitalsByDefault(true)
                .includeMedicationsByDefault(true)
                .includeNotesByDefault(false)
                .includeMoodPainByDefault(true)
                .includeAllergiesByDefault(true)
                .isActive(true)
                .build();

        assertThat(config.getId()).isEqualTo(1L);
        assertThat(config.getPatientId()).isEqualTo(10L);
        assertThat(config.getUserId()).isEqualTo(5L);
        assertThat(config.getPreferredAiProvider()).isEqualTo(AIProvider.OPENAI);
        assertThat(config.getOpenaiModel()).isEqualTo("gpt-4");
        assertThat(config.getDeepseekModel()).isEqualTo("deepseek-chat");
        assertThat(config.getMaxTokens()).isEqualTo(2048);
        assertThat(config.getTemperature()).isEqualTo(0.7);
        assertThat(config.getConversationHistoryLimit()).isEqualTo(10);
        assertThat(config.getSystemPrompt()).isEqualTo("You are a helpful medical assistant.");
        assertThat(config.getIncludeVitalsByDefault()).isTrue();
        assertThat(config.getIncludeMedicationsByDefault()).isTrue();
        assertThat(config.getIncludeNotesByDefault()).isFalse();
        assertThat(config.getIncludeMoodPainByDefault()).isTrue();
        assertThat(config.getIncludeAllergiesByDefault()).isTrue();
        assertThat(config.getIsActive()).isTrue();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final UserAIConfig config = new UserAIConfig();

        config.setPatientId(20L);
        config.setUserId(15L);
        config.setPreferredAiProvider(AIProvider.DEEPSEEK);
        config.setOpenaiModel("gpt-3.5-turbo");
        config.setDeepseekModel("deepseek-v2");
        config.setMaxTokens(1024);
        config.setTemperature(0.5);
        config.setConversationHistoryLimit(5);
        config.setSystemPrompt("Custom prompt");
        config.setIncludeVitalsByDefault(false);
        config.setIncludeMedicationsByDefault(false);
        config.setIncludeNotesByDefault(true);
        config.setIncludeMoodPainByDefault(false);
        config.setIncludeAllergiesByDefault(false);
        config.setIsActive(false);

        assertThat(config.getPatientId()).isEqualTo(20L);
        assertThat(config.getUserId()).isEqualTo(15L);
        assertThat(config.getPreferredAiProvider()).isEqualTo(AIProvider.DEEPSEEK);
        assertThat(config.getOpenaiModel()).isEqualTo("gpt-3.5-turbo");
        assertThat(config.getDeepseekModel()).isEqualTo("deepseek-v2");
        assertThat(config.getMaxTokens()).isEqualTo(1024);
        assertThat(config.getTemperature()).isEqualTo(0.5);
        assertThat(config.getConversationHistoryLimit()).isEqualTo(5);
        assertThat(config.getSystemPrompt()).isEqualTo("Custom prompt");
        assertThat(config.getIncludeVitalsByDefault()).isFalse();
        assertThat(config.getIncludeMedicationsByDefault()).isFalse();
        assertThat(config.getIncludeNotesByDefault()).isTrue();
        assertThat(config.getIncludeMoodPainByDefault()).isFalse();
        assertThat(config.getIncludeAllergiesByDefault()).isFalse();
        assertThat(config.getIsActive()).isFalse();
    }

    // ─── AIProvider.resolve() ─────────────────────────────────────────────────

    @Test
    void aiProvider_resolve_nullInput_returnsOpenAI() throws Exception {
        assertThat(AIProvider.resolve(null)).isEqualTo(AIProvider.OPENAI);
    }

    @Test
    void aiProvider_resolve_defaultString_returnsOpenAI() throws Exception {
        assertThat(AIProvider.resolve("DEFAULT")).isEqualTo(AIProvider.OPENAI);
    }

    @Test
    void aiProvider_resolve_openaiString_returnsOpenAI() throws Exception {
        assertThat(AIProvider.resolve("OPENAI")).isEqualTo(AIProvider.OPENAI);
    }

    @Test
    void aiProvider_resolve_deepseekString_returnsDeepSeek() throws Exception {
        assertThat(AIProvider.resolve("DEEPSEEK")).isEqualTo(AIProvider.DEEPSEEK);
    }

    @Test
    void aiProvider_resolve_caseInsensitive() throws Exception {
        assertThat(AIProvider.resolve("openai")).isEqualTo(AIProvider.OPENAI);
        assertThat(AIProvider.resolve("deepseek")).isEqualTo(AIProvider.DEEPSEEK);
    }

    @Test
    void aiProvider_resolve_unknownValue_returnsOpenAI() throws Exception {
        assertThat(AIProvider.resolve("UNKNOWN_PROVIDER")).isEqualTo(AIProvider.OPENAI);
    }

    // ─── AIProvider enum values ───────────────────────────────────────────────

    @Test
    void aiProvider_values() throws Exception {
        assertThat(AIProvider.values())
                .containsExactly(
                        AIProvider.DEFAULT,
                        AIProvider.OPENAI,
                        AIProvider.DEEPSEEK,
                        AIProvider.OLLAMA,
                        AIProvider.COLIBRI);
    }
}
