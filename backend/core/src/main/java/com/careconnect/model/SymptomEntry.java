package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;


@Entity
@Table(name = "symptom_entry")
@EqualsAndHashCode(callSuper = false)
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SymptomEntry extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_id")
    private Patient patient;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "caregiver_id")
    private Caregiver caregiver;

    @Builder.Default
    @Column(name = "completed", nullable = false)
    private Boolean completed = true;

    private String symptomKey;      // headache, cough, etc.
    private String symptomValue;    // “mild”, “severe”, “38.5 °C” …
    private Integer severity;       // 1-5 (nullable)

    @Column(name = "taken_at", nullable = false)
    private Instant takenAt;

    @Column(name = "notes", columnDefinition = "TEXT")
    private String notes;           //  Clinical notes
}
