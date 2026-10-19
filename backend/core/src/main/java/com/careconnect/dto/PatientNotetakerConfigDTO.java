package com.careconnect.dto;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.http.HttpStatus;

import com.careconnect.exception.AppException;
import com.careconnect.model.PatientNotetakerConfig;
import com.careconnect.model.PatientNotetakerKeyword;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;

@Builder
@Getter
@Setter
public class PatientNotetakerConfigDTO {
    private Long id;
    private Long patientId;
    private Boolean isEnabled;
    private Boolean permitCaregiverAccess;
    private List<PatientNotetakerKeyword> triggerKeywords;
    private LocalDateTime updatedAt;

    public PatientNotetakerConfigDTO() {
    }

    public PatientNotetakerConfigDTO(
            Long id,
            Long patientId,
            Boolean isEnabled,
            Boolean permitCaregiverAccess,
            List<PatientNotetakerKeyword> triggerKeywords,
            LocalDateTime updatedAt
    ) {
        this.id = id;
        this.patientId = patientId;
        this.isEnabled = isEnabled;
        this.permitCaregiverAccess = permitCaregiverAccess;
        this.triggerKeywords = triggerKeywords;
        this.updatedAt = updatedAt;
    }

    public PatientNotetakerConfigDTO(PatientNotetakerConfig config) {
        if (config != null) {
            this.id = config.getId();
            this.patientId = config.getPatientId();
            this.isEnabled = config.getIsEnabled();
            this.permitCaregiverAccess = config.getPermitCaregiverAccess();
            this.triggerKeywords = config.getTriggerKeywords();
            this.updatedAt = config.getUpdatedAt();
        } else {
            this.id = null;
            this.patientId = null;
            this.isEnabled = null;
            this.permitCaregiverAccess = null;
            this.triggerKeywords = null;
            this.updatedAt = null;
        }
    }

    public PatientNotetakerConfig toEntity() {
        return PatientNotetakerConfig.builder()
                .id(this.id)
                .patientId(this.patientId)
                .isEnabled(this.isEnabled)
                .permitCaregiverAccess(this.permitCaregiverAccess)
                .triggerKeywords(this.triggerKeywords)
                .updatedAt(this.updatedAt)
                .build();
    }
}


    

