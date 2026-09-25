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
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * Persisted patient consent granting a caregiver (or other grantee) access to a scoped
 * capability, such as {@code AI_RETRIEVAL} for Ask AI on_consent content (Task 2.4).
 */
@Entity
@Table(
        name = "consent_grants",
        indexes = {
                @Index(
                        name = "idx_consent_grants_lookup",
                        columnList = "patient_user_id, grantee_user_id, scope, status")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ConsentGrant {

    /**
     * Default scope used for Ask AI retrieval consent grants.
     */
    public static final String SCOPE_AI_RETRIEVAL = "AI_RETRIEVAL";

    /**
     * Status set while a grant is in force.
     */
    public static final String STATUS_ACTIVE = "ACTIVE";

    /**
     * Status set once a grant has been revoked.
     */
    public static final String STATUS_REVOKED = "REVOKED";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_user_id", nullable = false)
    private Long patientUserId;

    @Column(name = "grantee_user_id", nullable = false)
    private Long granteeUserId;

    @Column(name = "grantee_role", nullable = false, length = 32)
    private String granteeRole;

    @Column(name = "scope", nullable = false, length = 64)
    private String scope;

    @Column(name = "status", nullable = false, length = 24)
    private String status;

    @Column(name = "granted_at", nullable = false)
    private Instant grantedAt;

    @Column(name = "expires_at")
    private Instant expiresAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void onCreate() {
        final Instant now = Instant.now();
        if (scope == null) {
            scope = SCOPE_AI_RETRIEVAL;
        }
        if (status == null) {
            status = STATUS_ACTIVE;
        }
        if (grantedAt == null) {
            grantedAt = now;
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
}
