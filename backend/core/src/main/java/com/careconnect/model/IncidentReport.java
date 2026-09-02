package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "incident_reports")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class IncidentReport {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id
    @Column(name = "caregiver_id", nullable = false)
    private Long caregiverId; // caregiver.id
    @Enumerated(EnumType.STRING)
    @Column(name = "incident_type", nullable = false, length = 50)
    private IncidentType incidentType;
    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt;
    @Column(name = "location", nullable = false, columnDefinition = "TEXT")
    private String location;
    @Column(name = "trigger_notes", columnDefinition = "TEXT")
    private String triggerNotes;
    @Column(name = "outcome", nullable = false, columnDefinition = "TEXT")
    private String outcome;
    @Column(name = "created_by", nullable = false)
    private Long createdBy; // user.id
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
    @OneToMany(mappedBy = "incidentReport", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @Builder.Default
    private List<IncidentAction> actions = new ArrayList<>();

    @PrePersist
    public void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (occurredAt == null) occurredAt = createdAt;
    }

    @PreUpdate
    @PreRemove
    private void preventUpdateOrDelete() {
        throw new UnsupportedOperationException("IncidentReport records are immutable; updates and deletes are not allowed.");
    }

    public enum IncidentType {
        FALL,
        BEHAVIORAL_CRISIS,
        MEDICAL_EVENT,
        ELOPEMENT,
        SELF_HARM,
        PROPERTY_DAMAGE,
        OTHER
    }
}

