package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

/**
 * Maps a CareConnect patient to the identifier that same person carries in an external EHR,
 * one row per (patient, source).
 * <p>
 * The external identifier is retained for provenance and for addressing subsequent requests
 * to that source. It is <strong>not</strong> an authorization token and not grounds for a
 * merge: per FR-CERN-06 and BR-11, a raw external patient id, name or birth date alone must
 * never authorize access or trigger an automatic cross-source merge. Reconciliation of the
 * demographic fields behind these identifiers is a separate concern handled through
 * {@code ehr_source_identity}.
 * <p>
 * Both unique constraints are deliberately tight. {@code (source_id, external_patient_id)}
 * stops one external record being claimed by two patients; {@code (patient_id, source_id)}
 * allows a patient only one identifier per source. The second may need relaxing if
 * athenahealth sandbox output shows a patient legitimately holding several ids in one
 * source; loosening it later is cheap, whereas tightening it after bad data exists is not.
 * <p>
 * Stores bare {@code patientId}/{@code sourceId} rather than {@code @ManyToOne}, matching
 * {@code EhrAuditEvent}; the foreign keys are applied by {@code SchemaPatchRunner}. Timestamps
 * come from {@link Auditable}.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_patient_crosswalk",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uq_ehr_crosswalk_source_external",
                        columnNames = {"source_id", "external_patient_id"}),
                @UniqueConstraint(
                        name = "uq_ehr_crosswalk_patient_source",
                        columnNames = {"patient_id", "source_id"})
        },
        indexes = @Index(
                name = "idx_ehr_crosswalk_patient",
                columnList = "patient_id"))
public class EhrPatientCrosswalk extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /**
     * The patient's identifier within that source, e.g. a FHIR {@code Patient.id}. Stored
     * verbatim as the source reports it; never parsed for meaning.
     */
    @Column(name = "external_patient_id", nullable = false, length = 255)
    private String externalPatientId;
}
