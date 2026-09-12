package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import com.careconnect.model.Patient;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * One disputed field between the canonical patient record and a source snapshot.
 *
 * <p>Granularity is per field, not per patient and not per sync: a patient's name can be
 * confirmed from one source while their address is still unresolved from another, and a
 * single verification column on {@code patient} could not express that.
 *
 * <p>{@link #canonicalValue} and {@link #incomingValue} are denormalized snapshots taken at
 * detection time so the confirmation screen can render a diff without joining back to
 * {@link EhrSourceIdentity}, which may have moved on by the time the patient opens it.
 *
 * <p>Because the pending state lives here rather than in client memory, a force-quit, logout,
 * or crash before confirming loses nothing — the row stays {@code PENDING} and the prompt
 * reappears on the next login from any device.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "ehr_identity_conflict")
public class EhrIdentityConflict extends Auditable {

    /** Maximum length of the disputed field name. */
    private static final int FIELD_NAME_LENGTH = 64;

    /** Maximum length of the denormalized value snapshots. */
    private static final int VALUE_LENGTH = 255;

    /** Maximum length of the status column. */
    private static final int STATUS_LENGTH = 32;

    /** Maximum length of the resolver column. */
    private static final int RESOLVED_BY_LENGTH = 32;

    /** Database primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Patient whose record is in dispute. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    /** Source whose snapshot disagrees with the canonical value. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "source_id", nullable = false)
    private EhrSource source;

    /**
     * Column name of the disputed field, matching the {@link EhrSourceIdentity} column it was
     * compared from — for example {@code first_name}, {@code address_line1}, {@code date_of_birth}.
     */
    @Column(name = "field_name", nullable = false, length = FIELD_NAME_LENGTH)
    private String fieldName;

    /** Canonical patient value at the moment the conflict was detected. */
    @Column(name = "canonical_value", length = VALUE_LENGTH)
    private String canonicalValue;

    /** Source value at the moment the conflict was detected. */
    @Column(name = "incoming_value", length = VALUE_LENGTH)
    private String incomingValue;

    /** Resolution state. Never auto-expires into an assumed answer. */
    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = STATUS_LENGTH)
    private EhrConflictStatus status = EhrConflictStatus.PENDING;

    /** When the reconciler detected the disagreement. */
    @Column(name = "detected_at", nullable = false)
    private LocalDateTime detectedAt;

    /** When the conflict was resolved; null while pending. */
    @Column(name = "resolved_at")
    private LocalDateTime resolvedAt;

    /** Who resolved it; null while pending. */
    @Enumerated(EnumType.STRING)
    @Column(name = "resolved_by", length = RESOLVED_BY_LENGTH)
    private EhrConflictResolver resolvedBy;
}
