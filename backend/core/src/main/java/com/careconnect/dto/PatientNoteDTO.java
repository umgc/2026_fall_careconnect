package com.careconnect.dto;

import java.time.LocalDateTime;

import com.careconnect.model.PatientNote;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;

@Builder
@Getter
@Setter
public class PatientNoteDTO {
    private Long id;
    private Long patientId;
    private String note;
    private String aiSummary;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public PatientNoteDTO() {
    }

    public PatientNoteDTO(
            Long id,
            Long patientId,
            String note,
            String aiSummary,
            LocalDateTime createdAt,
            LocalDateTime updatedAt
    ) {
        this.id = id;
        this.patientId = patientId;
        this.note = note;
        this.aiSummary = aiSummary;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    public PatientNoteDTO(PatientNote patientNote) {
        if (patientNote != null) {
            this.id = patientNote.getId();
            this.patientId = patientNote.getPatientId();
            this.note = patientNote.getNote();
            this.aiSummary = patientNote.getAiSummary();
            this.createdAt = patientNote.getCreatedAt();
            this.updatedAt = patientNote.getUpdatedAt();
        } else {
            this.id = null;
            this.patientId = null;
            this.note = null;
            this.aiSummary = null;
            this.createdAt = null;
            this.updatedAt = null;
        }
    }

    public PatientNote toEntity() {
        return PatientNote.builder()
                .id(this.id)
                .patientId(this.patientId)
                .note(this.note)
                .aiSummary(this.aiSummary)
                .createdAt(createdAt)
                .updatedAt(updatedAt)
                .build();
    }
}


    

