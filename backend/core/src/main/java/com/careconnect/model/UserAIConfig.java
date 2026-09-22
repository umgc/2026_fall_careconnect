package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "user_ai_config")
public class UserAIConfig {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @jakarta.annotation.Nullable
    @Column(name = "patient_id", nullable = true)
    private Long patientId;

    @Column(name = "user_id", nullable = false)
    private Long userId;
    @Enumerated(EnumType.STRING)
    @Column(name = "preferred_ai_provider", nullable = false)
    private AIProvider preferredAiProvider;
    @Column(name = "openai_model")
    private String openaiModel;
    @Column(name = "deepseek_model")
    private String deepseekModel;
    @Column(name = "max_tokens")
    private Integer maxTokens;
    @Column(name = "temperature")
    private Double temperature;
    @Column(name = "conversation_history_limit")
    private Integer conversationHistoryLimit;
    @Column(name = "system_prompt", columnDefinition = "TEXT")
    private String systemPrompt;
    @Column(name = "include_vitals_by_default")
    private Boolean includeVitalsByDefault;
    @Column(name = "include_medications_by_default")
    private Boolean includeMedicationsByDefault;
    @Column(name = "include_notes_by_default")
    private Boolean includeNotesByDefault;
    @Column(name = "include_mood_pain_by_default")
    private Boolean includeMoodPainByDefault;
    @Column(name = "include_allergies_by_default")
    private Boolean includeAllergiesByDefault;
    @Column(name = "include_documents_by_default")
    private Boolean includeDocumentsByDefault;
    // Add isActive field for builder compatibility
    @Column(name = "is_active")
    private Boolean isActive;

    // Explicit getters and setters for compatibility
    public Long getPatientId() {
        return patientId;
    }

    public void setPatientId(Long patientId) {
        this.patientId = patientId;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public AIProvider getPreferredAiProvider() {
        return preferredAiProvider;
    }

    public void setPreferredAiProvider(AIProvider preferredAiProvider) {
        this.preferredAiProvider = preferredAiProvider;
    }

    public String getOpenaiModel() {
        return openaiModel;
    }

    public void setOpenaiModel(String openaiModel) {
        this.openaiModel = openaiModel;
    }

    public String getDeepseekModel() {
        return deepseekModel;
    }

    public void setDeepseekModel(String deepseekModel) {
        this.deepseekModel = deepseekModel;
    }

    public Integer getMaxTokens() {
        return maxTokens;
    }

    public void setMaxTokens(Integer maxTokens) {
        this.maxTokens = maxTokens;
    }

    public Double getTemperature() {
        return temperature;
    }

    public void setTemperature(Double temperature) {
        this.temperature = temperature;
    }

    public Integer getConversationHistoryLimit() {
        return conversationHistoryLimit;
    }

    public void setConversationHistoryLimit(Integer conversationHistoryLimit) {
        this.conversationHistoryLimit = conversationHistoryLimit;
    }

    public String getSystemPrompt() {
        return systemPrompt;
    }

    public void setSystemPrompt(String systemPrompt) {
        this.systemPrompt = systemPrompt;
    }

    public Boolean getIncludeVitalsByDefault() {
        return includeVitalsByDefault;
    }

    public void setIncludeVitalsByDefault(Boolean includeVitalsByDefault) {
        this.includeVitalsByDefault = includeVitalsByDefault;
    }

    public Boolean getIncludeMedicationsByDefault() {
        return includeMedicationsByDefault;
    }

    public void setIncludeMedicationsByDefault(Boolean includeMedicationsByDefault) {
        this.includeMedicationsByDefault = includeMedicationsByDefault;
    }

    public Boolean getIncludeNotesByDefault() {
        return includeNotesByDefault;
    }

    public void setIncludeNotesByDefault(Boolean includeNotesByDefault) {
        this.includeNotesByDefault = includeNotesByDefault;
    }

    public Boolean getIncludeMoodPainByDefault() {
        return includeMoodPainByDefault;
    }

    public void setIncludeMoodPainByDefault(Boolean includeMoodPainByDefault) {
        this.includeMoodPainByDefault = includeMoodPainByDefault;
    }

    public Boolean getIncludeAllergiesByDefault() {
        return includeAllergiesByDefault;
    }

    public void setIncludeAllergiesByDefault(Boolean includeAllergiesByDefault) {
        this.includeAllergiesByDefault = includeAllergiesByDefault;
    }

    public Boolean getIncludeDocumentsByDefault() {
        return includeDocumentsByDefault;
    }

    public void setIncludeDocumentsByDefault(Boolean includeDocumentsByDefault) {
        this.includeDocumentsByDefault = includeDocumentsByDefault;
    }

    public Boolean getIsActive() {
        return isActive;
    }

    public void setIsActive(Boolean isActive) {
        this.isActive = isActive;
    }

    public enum AIProvider {
        DEFAULT,
        OPENAI,
        DEEPSEEK;

        public static AIProvider resolve(String value) {
            if (value == null) return OPENAI;
            if (value.equalsIgnoreCase("DEFAULT")) return OPENAI;
            for (AIProvider p : values()) {
                if (p.name().equalsIgnoreCase(value)) return p;
            }
            return OPENAI;
        }
    }
    // ...rest of the code...
}
