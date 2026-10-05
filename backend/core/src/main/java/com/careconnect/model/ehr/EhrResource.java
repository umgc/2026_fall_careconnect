package com.careconnect.model.ehr;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * Authoritative, provenance-tagged mirror of one fetched Epic FHIR resource (Epic Phase 1).
 *
 * <p>Epic-origin data is stored here — <b>never</b> merged into the app's self-entered
 * Patient/Medication/Allergy rows (Open Item O1: no clobbering) — so it is cleanly deletable on
 * disconnect and is the authoritative row the indexer loads for {@code EPIC_FHIR_INDEXED}
 * (mirroring how {@code PatientNote} backs {@code CLINICAL_NOTE_INDEXED}). Also serves as the
 * provenance/de-dup record ({@code (userId, source, resourceType, resourceFhirId)} unique).
 * The raw FHIR JSON is retained for later reconciliation (deferred R5/R7).
 */
@Entity
@Table(
        name = "ehr_resource",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_resource_identity",
                columnNames = {"user_id", "source", "resource_type", "resource_fhir_id"}),
        indexes = {
                @Index(name = "idx_ehr_resource_user", columnList = "user_id"),
                @Index(name = "idx_ehr_resource_user_type", columnList = "user_id, resource_type")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EhrResource {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** CareConnect user (patient) id — the RBAC/indexing scope key. */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "source", nullable = false, length = 32)
    private String source;

    /** FHIR resourceType, e.g. "Condition", "MedicationRequest". */
    @Column(name = "resource_type", nullable = false, length = 48)
    private String resourceType;

    @Column(name = "resource_fhir_id", nullable = false, length = 255)
    private String resourceFhirId;

    /** FHIR status/clinicalStatus that passed the status gate. */
    @Column(name = "status_value", length = 48)
    private String statusValue;

    /** Human-readable one-line title for citations. */
    @Column(name = "title", length = 512)
    private String title;

    /** ISO-8601 clinical timestamp when derivable (effective/onset/authored/date). */
    @Column(name = "occurred_at", length = 40)
    private String occurredAt;

    @Column(name = "content_hash", length = 128)
    private String contentHash;

    @Lob
    @Column(name = "payload_json")
    private String payloadJson;

    @Column(name = "last_synced_at", nullable = false)
    private Instant lastSyncedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    void onCreate() {
        final Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        lastSyncedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        lastSyncedAt = Instant.now();
    }
}
