package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "clinical_notes")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ClinicalNote {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "caregiver_id")
    private Long caregiverId;

    @Column(name = "note_type")
    private String noteType; // ASSESSMENT, PLAN, OBSERVATION, etc.

    @Column(columnDefinition = "TEXT")
    private String content;

    @Column(name = "subject")
    private String subject;

    @Column(name = "is_active")
    @Builder.Default
    private Boolean isActive = true;

    @Column(name = "created_at")
    @Builder.Default
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PreUpdate
    void preUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}
