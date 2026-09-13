package com.careconnect.model.ehr;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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
 * Encrypted per-user EHR OAuth credential (Phase 0 / doc 1_8, Findings R1).
 *
 * <p>Generalized ({@code ehr_credentials}, source-parameterized) rather than overloading
 * {@code EmailCredential} (whose {@code userId} is a String and whose {@code Provider} enum
 * carries a DB CHECK constraint). {@code source} = "EPIC" today; Medicare/Aetna/Oracle become
 * sibling rows later. The {@code (user_id, source)} pair is the single-source form of the
 * future identity crosswalk (Findings R4, deferred).
 *
 * <p>Access/refresh tokens are encrypted at rest via {@link com.careconnect.security.TokenCryptor}.
 */
@Entity
@Table(
        name = "ehr_credentials",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_credentials_user_source",
                columnNames = {"user_id", "source"}),
        indexes = {
                @Index(name = "idx_ehr_credentials_user", columnList = "user_id"),
                @Index(name = "idx_ehr_credentials_user_source", columnList = "user_id, source")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EhrCredential {

    public enum Status { ACTIVE, NEEDS_REAUTH, DISCONNECTED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "source", nullable = false, length = 32)
    private String source;

    @Column(name = "patient_fhir_id", length = 64)
    private String patientFhirId;

    @Column(name = "fhir_base_url", length = 512)
    private String fhirBaseUrl;

    @Lob
    @Column(name = "access_token_enc")
    private String accessTokenEnc;

    @Lob
    @Column(name = "refresh_token_enc")
    private String refreshTokenEnc;

    @Column(name = "scopes", length = 1024)
    private String scopes;

    @Column(name = "expires_at")
    private Instant expiresAt;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private Status status;

    @Column(name = "last_error", length = 512)
    private String lastError;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void onCreate() {
        final Instant now = Instant.now();
        if (status == null) {
            status = Status.ACTIVE;
        }
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public Status getStatus() {
        return status == null ? Status.ACTIVE : status;
    }
}
