package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(name = "patient_medication")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Medication {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    @Column(name = "medication_name", nullable = false)
    private String medicationName;

    @Column(name = "dosage")
    private String dosage; // e.g., "10mg", "2 tablets"

    @Column(name = "frequency")
    private String frequency; // e.g., "twice daily", "every 8 hours"

    @Column(name = "route")
    private String route; // e.g., "oral", "injection", "topical"

    @Enumerated(EnumType.STRING)
    @Column(name = "medication_type")
    private MedicationType medicationType;

    @Column(name = "prescribed_by")
    private String prescribedBy; // Doctor's name

    @Column(name = "prescribed_date")
    private String prescribedDate;

    @Column(name = "start_date")
    private String startDate;

    @Column(name = "end_date")
    private String endDate; // null for ongoing medications

    @Column(name = "notes", columnDefinition = "TEXT")
    private String notes; // Additional instructions or notes

    @Builder.Default
    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    // 🟢 NEW FIELD: approval_status
    @Builder.Default
    @Column(name = "approval_status", length = 20, nullable = false)
    private String approvalStatus = "PENDING";

    @Column(name = "last_taken")
    private Instant lastTaken;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        this.createdAt = now;
        this.updatedAt = now;

        if (this.isActive == null) {
            this.isActive = true;
        }
        if (this.approvalStatus == null) {
            this.approvalStatus = "PENDING";
        }
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = Instant.now();
    }

    // ENUM for medication type
    public enum MedicationType {
        PRESCRIPTION("Prescription"),
        OVER_THE_COUNTER("Over-the-counter"),
        SUPPLEMENT("Supplement/Vitamin"),
        HERBAL("Herbal/Natural"),
        EMERGENCY("Emergency Medication");

        private final String displayName;

        MedicationType(String displayName) {
            this.displayName = displayName;
        }

        public String getDisplayName() {
            return displayName;
        }
    }
}
