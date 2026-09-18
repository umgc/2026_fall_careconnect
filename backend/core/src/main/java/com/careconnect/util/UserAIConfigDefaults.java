package com.careconnect.util;

import com.careconnect.model.UserAIConfig;

/**
 * Centralized default configurations for AI services
 */
public class UserAIConfigDefaults {

    public static final String MEDICAL_SYSTEM_PROMPT =
            "You are an AI assistant that helps patients access their health information. " +
                    "You are NOT a medical professional and cannot provide medical advice, diagnosis, or treatment. " +
                    "State facts from the patient's records without clinical interpretation. " +
                    "For medical concerns, direct users to contact their healthcare provider. " +
                    "For emergencies, instruct users to call 911 or go to the emergency room immediately. " +
                    "Keep responses factual, clear, and focused on information access rather than clinical assessment.";

    public static final String CAREGIVER_SYSTEM_PROMPT =
            "You are an AI assistant for healthcare caregivers. Provide professional guidance on patient care best practices, " +
                    "care management strategies, administrative support, and general medical knowledge for healthcare professionals. " +
                    "You can discuss clinical concepts, care protocols, and evidence-based practices, but always emphasize that " +
                    "final medical decisions should be made by licensed healthcare providers. For patient-specific situations, " +
                    "recommend consulting with supervising physicians or following established clinical protocols.";

    public static final String GENERIC_SYSTEM_PROMPT = "You are a helpful assistant.";

    public static final UserAIConfig.AIProvider DEFAULT_PROVIDER = UserAIConfig.AIProvider.DEEPSEEK;
    public static final Integer DEFAULT_MAX_TOKENS = 2048;
    public static final Double DEFAULT_TEMPERATURE = 0.7;
    public static final Integer DEFAULT_CONVERSATION_HISTORY_LIMIT = 10;

    /**
     * Create default configuration for medical/patient contexts
     */
    public static UserAIConfig createMedicalDefaultConfig(Long userId, Long patientId) {
        return UserAIConfig.builder()
                .userId(userId)
                .patientId(patientId)
                .preferredAiProvider(DEFAULT_PROVIDER)
                .maxTokens(DEFAULT_MAX_TOKENS)
                .temperature(DEFAULT_TEMPERATURE)
                .conversationHistoryLimit(DEFAULT_CONVERSATION_HISTORY_LIMIT)
                .systemPrompt(MEDICAL_SYSTEM_PROMPT)
                .includeVitalsByDefault(true)
                .includeMedicationsByDefault(true)
                .includeNotesByDefault(true)
                .includeMoodPainByDefault(true)
                .includeAllergiesByDefault(true)
                .includeDocumentsByDefault(true)
                .isActive(true)
                .build();
    }

    /**
     * Get the appropriate system prompt for the context
     */
    public static String getSystemPrompt(UserAIConfig config) {
        if (config != null && config.getSystemPrompt() != null && !config.getSystemPrompt().trim().isEmpty()) {
            return config.getSystemPrompt();
        }
        return config != null && config.getPatientId() != null ? MEDICAL_SYSTEM_PROMPT : GENERIC_SYSTEM_PROMPT;
    }
}