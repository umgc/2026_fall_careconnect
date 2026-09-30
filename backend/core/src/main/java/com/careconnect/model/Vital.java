package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "vitals")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Vital {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "vital_type", nullable = false)
    private String vitalType; // BLOOD_PRESSURE, HEART_RATE, TEMPERATURE, etc.

    @Column(name = "value", nullable = false)
    private String value; // Store as string to handle different formats (e.g., "120/80", "98.6", "72")

    @Column(name = "unit")
    private String unit; // mmHg, bpm, °F, etc.

    @Column(name = "recorded_at", nullable = false)
    @Builder.Default
    private LocalDateTime recordedAt = LocalDateTime.now();

    @Column(name = "recorded_by")
    private Long recordedBy; // User ID who recorded the vital

    @Column(name = "notes")
    private String notes;

    @Column(name = "is_abnormal")
    @Builder.Default
    private Boolean isAbnormal = false;

    @Column(name = "created_at")
    @Builder.Default
    private LocalDateTime createdAt = LocalDateTime.now();
}
