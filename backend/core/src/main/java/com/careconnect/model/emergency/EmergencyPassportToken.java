package com.careconnect.model.emergency;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * The code behind a patient's Emergency Care Passport QR (CC-12, Increment 2).
 * <p>
 * Follows {@code InviteToken}'s design: the raw token is never stored. {@code tokenLookup} is its
 * non-secret 16-character prefix, used to find the row; {@code tokenHash} is a BCrypt hash of the
 * whole token. The raw token is returned once, when the code is made, and lives only in the QR.
 * <p>
 * There is deliberately no expiry. The QR is meant to sit on a lock screen indefinitely, so a timer
 * would silently break it; revocation is the safety control instead. Making a new code revokes the
 * old one, and at most one row per patient is {@link Status#ACTIVE}, which a partial unique index
 * applied by {@code SchemaPatchRunner} enforces.
 * <p>
 * {@code lastScannedAt} is the only usage record for M4; a full scan audit trail is deferred.
 * Stores a bare {@code patientId}; the foreign key, with {@code ON DELETE CASCADE}, is applied by
 * {@code SchemaPatchRunner}. Timestamps come from {@link Auditable}.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "emergency_passport_token",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_emergency_passport_token_lookup",
                columnNames = "token_lookup"),
        indexes = @Index(
                name = "idx_emergency_passport_token_patient",
                columnList = "patient_id"))
public class EmergencyPassportToken extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "token_lookup", nullable = false, length = 32)
    private String tokenLookup;

    @Column(name = "token_hash", nullable = false, length = 255)
    private String tokenHash;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private Status status;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    /** Null until the code is first scanned. */
    @Column(name = "last_scanned_at")
    private Instant lastScannedAt;

    public boolean isActive() {
        return status == Status.ACTIVE;
    }

    public enum Status {
        ACTIVE,
        REVOKED
    }
}
