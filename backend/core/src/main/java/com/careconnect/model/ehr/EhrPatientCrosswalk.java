package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import com.careconnect.model.Patient;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Maps one source's own patient identifier to CareConnect's internal {@link Patient}.
 *
 * <p>This is the identity-resolution problem, kept separate from demographic disagreement
 * ({@link EhrIdentityConflict}): a crosswalk row answers "which internal patient is this
 * external id," not "which value should we trust." An adapter looks up its row here before it
 * can fetch or write anything else for a patient, since every downstream call to the source's
 * API is keyed by {@link #externalPatientId}, not {@code patient_id}.
 *
 * <p>Uniqueness is enforced two ways at the database level (see the accompanying schema patch):
 * {@code (source_id, external_patient_id)} — one external identity maps to at most one internal
 * patient — and {@code (patient_id, source_id)} — one external id per patient per source. The
 * second assumes a source never exposes multiple identifiers for the same patient; if that
 * assumption breaks for a given source, that constraint needs to relax to allow multiples.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "ehr_patient_crosswalk")
public class EhrPatientCrosswalk extends Auditable {

    /** Maximum length of the source's own patient identifier. */
    private static final int EXTERNAL_PATIENT_ID_LENGTH = 128;

    /** Database primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Internal patient this external identity resolves to. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    /** Source that issued the external identifier. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "source_id", nullable = false)
    private EhrSource source;

    /**
     * The source's own identifier for this patient, for example a FHIR {@code Patient.id},
     * an MRN, or an MBI. Adapters key every fetch to the source's API off this value.
     */
    @Column(name = "external_patient_id", nullable = false, length = EXTERNAL_PATIENT_ID_LENGTH)
    private String externalPatientId;
}
