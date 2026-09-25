package com.careconnect.dto;

import com.careconnect.model.ChatConversation;
import com.careconnect.service.MedicalDataAnonymizer.AnonymizationLevel;
import jakarta.validation.constraints.*;
import lombok.*;

import java.util.List;

import com.careconnect.dto.UploadedFileDTO;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder(toBuilder = true)
public class ChatRequest {

    @Size(max = 5000, message = "Message content cannot exceed 5000 characters")
    private String message;
    private String conversationId; // Optional - will create new if not provided
    private Long patientId;
    @NotNull(message = "User ID is required")
    private Long userId;
    @Builder.Default
    private ChatConversation.ChatType chatType = ChatConversation.ChatType.GENERAL_SUPPORT;
    // Context override options
    private Boolean includeVitals;
    private Boolean includeMedications;
    private Boolean includeNotes;
    private Boolean includeMoodPainLogs;
    private Boolean includeAllergies;
    private Boolean includeDocuments;
    // AI Configuration overrides
    private Double temperature;
    private Integer maxTokens;
    private String preferredModel;
    // Additional context
    private List<String> additionalContext;
    private List<UploadedFileDTO> uploadedFiles; // Optional: uploaded files passed in the request
    private String title; // Optional conversation title
    // Privacy and anonymization settings
    @Builder.Default
    private AnonymizationLevel anonymizationLevel = AnonymizationLevel.MODERATE;
    @Builder.Default
    private Boolean enableDifferentialPrivacy = false;
    @Builder.Default
    private Boolean statisticalSummaryOnly = false;
    @Builder.Default
    private Boolean privacyConsent = false;
    private Integer dataRetentionDays; // Override default retention

    // Explicit getters and setters for compatibility
    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getConversationId() {
        return conversationId;
    }

    public void setConversationId(String conversationId) {
        this.conversationId = conversationId;
    }

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

    public ChatConversation.ChatType getChatType() {
        return chatType;
    }

    public void setChatType(ChatConversation.ChatType chatType) {
        this.chatType = chatType;
    }

    public String getPreferredModel() {
        return preferredModel;
    }

    public void setPreferredModel(String preferredModel) {
        this.preferredModel = preferredModel;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    // Explicit getter for compatibility
    public List<UploadedFileDTO> getUploadedFiles() {
        return uploadedFiles;
    }

    // Convenience methods for boolean checks
    public Double getTemperature() {
        return temperature;
    }

    public boolean isIncludeVitals() {
        return includeVitals != null ? includeVitals : false;
    }

    public boolean isIncludeMedications() {
        return includeMedications != null ? includeMedications : false;
    }

    public boolean isIncludeNotes() {
        return includeNotes != null ? includeNotes : false;
    }

    public boolean isIncludeMoodPainLogs() {
        return includeMoodPainLogs != null ? includeMoodPainLogs : false;
    }

    public boolean isIncludeAllergies() {
        return includeAllergies != null ? includeAllergies : false;
    }

    public boolean isEnableDifferentialPrivacy() {
        return enableDifferentialPrivacy != null ? enableDifferentialPrivacy : false;
    }

    public boolean isStatisticalSummaryOnly() {
        return statisticalSummaryOnly != null ? statisticalSummaryOnly : false;
    }

    public boolean isPrivacyConsent() {
        return privacyConsent != null ? privacyConsent : false;
    }
}
