package com.careconnect.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;
import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(name = "patient_allergy")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
@EqualsAndHashCode(exclude = {"patient"})
public class Allergy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;
    @Column(name = "allergen", nullable = false)
    private String allergen;
    @Column(name = "allergy_type")
    @Enumerated(EnumType.STRING)
    private AllergyType allergyType;
    @Column(name = "severity")
    @Enumerated(EnumType.STRING)
    private AllergySeverity severity;
    @Column(name = "reaction", columnDefinition = "TEXT")
    private String reaction;
    @Column(name = "notes", columnDefinition = "TEXT")
    private String notes;
    @Column(name = "diagnosed_date")
    private String diagnosedDate; // keep String to match frontend
    @Column(name = "is_active", nullable = false)
    @Builder.Default
    private Boolean isActive = true;
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
    @Column(name = "updated_at")
    private Instant updatedAt;

    public Long getId() {
        return id;
    }

    public Patient getPatient() {
        return patient;
    }

    // setters for updates
    public void setAllergen(String allergen) {
        this.allergen = allergen;
    }

    public void setAllergyType(AllergyType allergyType) {
        this.allergyType = allergyType;
    }

    public void setSeverity(AllergySeverity severity) {
        this.severity = severity;
    }

    public void setReaction(String reaction) {
        this.reaction = reaction;
    }

    public void setNotes(String notes) {
        this.notes = notes;
    }

    public void setDiagnosedDate(String diagnosedDate) {
        this.diagnosedDate = diagnosedDate;
    }

    public void setIsActive(Boolean isActive) {
        this.isActive = isActive;
    }

    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        this.createdAt = now;
        this.updatedAt = now;
        if (this.isActive == null) this.isActive = true;
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = Instant.now();
    }

    // Enums (nested enums are implicitly static—good)
    public enum AllergyType {
        FOOD("Food Allergy"),
        MEDICATION("Medication Allergy"),
        ENVIRONMENTAL("Environmental Allergy"),
        CONTACT("Contact Allergy"),
        SEASONAL("Seasonal Allergy"),
        OTHER("Other");

        private final String displayName;

        AllergyType(String displayName) {
            this.displayName = displayName;
        }

        @JsonCreator(mode = JsonCreator.Mode.DELEGATING)
        public static AllergyType fromJson(String raw) {
            if (raw == null) return OTHER;
            String v = raw.trim().toUpperCase();
            switch (v) {
                case "DRUG":
                case "MEDICATION":
                    return MEDICATION;
                case "FOOD":
                    return FOOD;
                case "ENVIRONMENTAL":
                    return ENVIRONMENTAL;
                case "CONTACT":
                    return CONTACT;
                case "SEASONAL":
                    return SEASONAL;
                case "OTHER":
                    return OTHER;
                default:
                    return OTHER;
            }
        }

        public String getDisplayName() {
            return displayName;
        }

        @JsonValue
        public String toJson() {
            return name();
        }
    }

    public enum AllergySeverity {
        MILD("Mild"),
        MODERATE("Moderate"),
        SEVERE("Severe"),
        LIFE_THREATENING("Life-threatening");

        private final String displayName;

        AllergySeverity(String displayName) {
            this.displayName = displayName;
        }

        @JsonCreator(mode = JsonCreator.Mode.DELEGATING)
        public static AllergySeverity fromJson(String raw) {
            if (raw == null) return MILD;
            String v = raw.trim().toUpperCase();
            switch (v) {
                case "MILD":
                    return MILD;
                case "MODERATE":
                    return MODERATE;
                case "SEVERE":
                    return SEVERE;
                case "LIFE_THREATENING":
                    return LIFE_THREATENING;
                default:
                    return MILD;
            }
        }

        public String getDisplayName() {
            return displayName;
        }

        @JsonValue
        public String toJson() {
            return name();
        }
    }
}
