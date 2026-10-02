package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;

/**
 * Verbatim FHIR response body as returned by an external EHR source, kept so a mapping can be
 * re-derived or audited without re-querying the source.
 * <p>
 * <strong>This table is PHI-bearing.</strong> Unlike {@code ehr_audit_event.details}, the
 * payload holds retrieved clinical content, so it is subject to the retention and deletion
 * rules that apply to patient data.
 * <p>
 * <strong>No retention period is set for it yet.</strong> The purge exists
 * ({@code EhrRawPayloadRetentionWorker}, {@code careconnect.ehr.raw-payload.retention-days}) but
 * defaults to off, because how long a verbatim payload may be kept is a policy decision nobody has
 * made -- raised by @SungWook1207 on PR #209, 2026-09-30, and again on PR #216. An earlier version of
 * this note said "a Table 47 retention row is still outstanding"; the TDD's tables run 1 to 13 and
 * no Table 47 exists in any document in this repository, so that reference has been removed. The
 * gap is tracked as issue #214, and belongs with the WBS 1.8 HIPAA
 * production gate, which already blocks production merges until retention evidence is attached.
 * <p>
 * Photographs are stripped before insert, never stored and trimmed afterwards: callers remove
 * {@code Patient.photo} (and any other inline binary) from the body and set
 * {@code photoStripped}, so full image bytes are never written to this column at all. That
 * keeps PHI minimal by construction and avoids needing a size-based cleanup job.
 * <p>
 * Stores bare {@code patientId}/{@code sourceId} rather than {@code @ManyToOne}, matching
 * {@code EhrAuditEvent}; the foreign keys are applied by {@code SchemaPatchRunner}.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_raw_payload",
        indexes = {
                @Index(
                        name = "idx_ehr_raw_payload_patient_resource",
                        columnList = "patient_id, source_id, resource_type"),
                @Index(
                        name = "idx_ehr_raw_payload_retrieved_at",
                        columnList = "retrieved_at")
        })
public class EhrRawPayload extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /** FHIR resource the body describes, e.g. Patient, Coverage, Appointment. */
    @Column(name = "resource_type", nullable = false, length = 64)
    private String resourceType;

    /**
     * The resource's own id within the source, when the body describes a single resource.
     * Null for a Bundle or a search result covering several.
     */
    @Column(name = "external_resource_id", length = 255)
    private String externalResourceId;

    /**
     * Response body exactly as received, minus any stripped binary. Held as text rather than a
     * parsed map so re-derivation sees what the source actually sent, byte for byte.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload", nullable = false, columnDefinition = "jsonb")
    private String payload;

    /**
     * UTF-8 byte length of {@link #payload}, derived on insert. Recorded so payload growth can
     * be measured against a cap before one is set, rather than guessed.
     */
    @Column(name = "payload_size_bytes", nullable = false)
    private Integer payloadSizeBytes;

    /** True when inline binary was removed from the body before it was stored. */
    @Column(name = "photo_stripped", nullable = false)
    @Builder.Default
    private Boolean photoStripped = Boolean.FALSE;

    /**
     * When the source actually answered. Distinct from {@link Auditable}'s {@code created_at},
     * which records when this row was written: a caller may store a response it fetched
     * earlier, so these are not interchangeable.
     */
    @Column(name = "retrieved_at", nullable = false)
    private OffsetDateTime retrievedAt;

    /**
     * Named to avoid colliding with {@link Auditable}'s own {@code onCreate} callback, which
     * JPA invokes first.
     */
    @PrePersist
    void applyDefaults() {
        if (retrievedAt == null) {
            retrievedAt = OffsetDateTime.now();
        }
        if (photoStripped == null) {
            photoStripped = Boolean.FALSE;
        }
        payloadSizeBytes = payload == null
                ? 0
                : payload.getBytes(StandardCharsets.UTF_8).length;
    }
}
