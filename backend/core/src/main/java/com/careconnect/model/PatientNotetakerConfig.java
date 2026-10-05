package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.List;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;


@Entity
@Table(name = "patient_note_taker_config")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PatientNotetakerConfig {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "is_enabled", nullable = false)
    private Boolean isEnabled;

    @Column(name = "permit_caregiver_access", nullable = false)
    private Boolean permitCaregiverAccess;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "trigger_keywords", nullable = true, columnDefinition = "jsonb")
    private List<PatientNotetakerKeyword> triggerKeywords;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;
}




