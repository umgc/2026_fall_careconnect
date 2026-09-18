package com.careconnect.dto;

import com.careconnect.model.UserAIConfig.AIProvider;
import jakarta.validation.constraints.*;
import lombok.*;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserAIConfigDTO {
    private Long id;
    private Long patientId;
    @NotNull(message = "User ID is required")
    private Long userId;
    @NotNull(message = "AI provider is required")
    private AIProvider aiProvider;
    @Builder.Default
    private String openaiModel = "gpt-4";
    @Builder.Default
    private String deepseekModel = "deepseek-chat";
    @Min(value = 100, message = "Max tokens must be at least 100")
    @Max(value = 8000, message = "Max tokens cannot exceed 8000")
    @Builder.Default
    private Integer maxTokens = 200;
    @DecimalMin(value = "0.0", message = "Temperature must be between 0.0 and 2.0")
    @DecimalMax(value = "2.0", message = "Temperature must be between 0.0 and 2.0")
    @Builder.Default
    private Double temperature = 0.7;
    @Min(value = 5, message = "Conversation history limit must be at least 5")
    @Max(value = 100, message = "Conversation history limit cannot exceed 100")
    @Builder.Default
    private Integer conversationHistoryLimit = 20;
    // Default context inclusion preferences
    @Builder.Default
    private Boolean includeVitalsByDefault = true;
    @Builder.Default
    private Boolean includeMedicationsByDefault = true;
    @Builder.Default
    private Boolean includeNotesByDefault = true;
    @Builder.Default
    private Boolean includeMoodPainLogsByDefault = true;
    @Builder.Default
    private Boolean includeAllergiesByDefault = true;
    @Builder.Default
    private Boolean includeDocumentsByDefault = true;
    @Builder.Default
    private Boolean isActive = true;
    private String systemPrompt;

    // Explicit getters for compatibility
    public Long getId() {
        return id;
    }

    public Long getUserId() {
        return userId;
    }

    public Long getPatientId() {
        return patientId;
    }

    public AIProvider getAiProvider() {
        return aiProvider;
    }

    public String getOpenaiModel() {
        return openaiModel;
    }

    public String getDeepseekModel() {
        return deepseekModel;
    }

    public Integer getMaxTokens() {
        return maxTokens;
    }

    public Double getTemperature() {
        return temperature;
    }

    public Integer getConversationHistoryLimit() {
        return conversationHistoryLimit;
    }

    public Boolean getIncludeVitalsByDefault() {
        return includeVitalsByDefault;
    }

    public Boolean getIncludeMedicationsByDefault() {
        return includeMedicationsByDefault;
    }

    public Boolean getIncludeNotesByDefault() {
        return includeNotesByDefault;
    }

    public Boolean getIncludeMoodPainLogsByDefault() {
        return includeMoodPainLogsByDefault;
    }

    public Boolean getIncludeAllergiesByDefault() {
        return includeAllergiesByDefault;
    }

    public Boolean getIncludeDocumentsByDefault() {
        return includeDocumentsByDefault;
    }

    public Boolean getIsActive() {
        return isActive;
    }

    public String getSystemPrompt() {
        return systemPrompt;
    }
}
