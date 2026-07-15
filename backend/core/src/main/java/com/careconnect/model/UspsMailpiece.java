package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * Durable USPS Informed Delivery mailpiece (Task 3.14.5 / #122).
 * Distinct from the API/cache DTO {@link MailPiece}.
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "usps_mailpiece",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uq_usps_mailpiece_patient_source_key",
                        columnNames = {"patient_id", "source_key"})
        },
        indexes = {
                @Index(name = "idx_usps_mailpiece_patient_digest_date",
                        columnList = "patient_id, digest_date"),
                @Index(name = "idx_usps_mailpiece_patient_content_hash",
                        columnList = "patient_id, content_hash")
        }
)
public class UspsMailpiece {

    private static final int USER_ID_LENGTH = 120;
    private static final int SOURCE_KEY_LENGTH = 160;
    private static final int EXTERNAL_ID_LENGTH = 120;
    private static final int SENDER_LENGTH = 512;
    private static final int IMAGE_REF_LENGTH = 1024;
    private static final int CONTENT_HASH_LENGTH = 80;
    private static final int CONSENT_SCOPE_LENGTH = 40;
    private static final int IMPORTANCE_LEVEL_LENGTH = 16;
    private static final int CLASSIFICATION_METHOD_LENGTH = 32;
    private static final int CLASSIFICATION_ENGINE_LENGTH = 128;
    private static final int IMPORTANCE_CATEGORY_LENGTH = 40;
    private static final int IMPORTANCE_CONFIDENCE_PRECISION = 3;
    private static final int IMPORTANCE_CONFIDENCE_SCALE = 2;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "user_id", length = USER_ID_LENGTH)
    private String userId;

    @Column(name = "source_key", nullable = false, length = SOURCE_KEY_LENGTH)
    private String sourceKey;

    @Column(name = "external_id", length = EXTERNAL_ID_LENGTH)
    private String externalId;

    @Column(name = "sender", length = SENDER_LENGTH)
    private String sender;

    @Column(name = "summary", columnDefinition = "TEXT")
    private String summary;

    @Column(name = "image_ref", length = IMAGE_REF_LENGTH)
    private String imageRef;

    @Column(name = "received_at")
    private OffsetDateTime receivedAt;

    @Column(name = "digest_date")
    private LocalDate digestDate;

    @Column(name = "ocr_text", columnDefinition = "TEXT")
    private String ocrText;

    @Column(name = "content_hash", nullable = false, length = CONTENT_HASH_LENGTH)
    private String contentHash;

    @Column(name = "consent_scope", length = CONSENT_SCOPE_LENGTH)
    private String consentScope;

    /** Importance tier: HIGH, MODERATE, LOW, UNKNOWN (Task 3.14.6). */
    @Column(name = "importance_level", length = IMPORTANCE_LEVEL_LENGTH)
    private String importanceLevel;

    @Column(name = "importance_confidence",
            precision = IMPORTANCE_CONFIDENCE_PRECISION,
            scale = IMPORTANCE_CONFIDENCE_SCALE)
    private BigDecimal importanceConfidence;

    /** RULES, AI, or HYBRID. */
    @Column(name = "classification_method", length = CLASSIFICATION_METHOD_LENGTH)
    private String classificationMethod;

    @Column(name = "classification_engine", length = CLASSIFICATION_ENGINE_LENGTH)
    private String classificationEngine;

    @Column(name = "importance_reasoning", columnDefinition = "TEXT")
    private String importanceReasoning;

    /** MEDICAL, FINANCIAL, LEGAL, ADMINISTRATIVE, MARKETING, OTHER. */
    @Column(name = "importance_category", length = IMPORTANCE_CATEGORY_LENGTH)
    private String importanceCategory;

    @Column(name = "classified_at")
    private OffsetDateTime classifiedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    void onCreate() {
        final OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = OffsetDateTime.now(ZoneOffset.UTC);
    }
}
