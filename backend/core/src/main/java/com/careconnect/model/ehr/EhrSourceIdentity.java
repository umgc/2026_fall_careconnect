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
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * Per-source demographic snapshot of one patient, as most recently seen at that source.
 *
 * <p>This is the only table an EHR adapter writes. Adapters never touch {@code patient}
 * directly; the shared reconciliation service is the sole writer of canonical values. Each
 * adapter upserts its own row keyed by {@code (patient_id, source_id)}, which makes a sync
 * idempotent and safe to retry after an interrupted fetch.
 *
 * <p>Values here are normalized on the way in — notably {@link #dateOfBirth} is a real
 * {@link LocalDate}, so that {@code 1985-03-02} from one source and {@code 03/02/1985} from
 * another do not register as a conflict when they are the same date.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "ehr_source_identity")
public class EhrSourceIdentity extends Auditable {

    /** Maximum length of the source's own patient identifier. */
    private static final int SOURCE_PATIENT_ID_LENGTH = 128;

    /** Maximum length of name and address-line columns. */
    private static final int NAME_LENGTH = 255;

    /** Maximum length of the phone column. */
    private static final int PHONE_LENGTH = 64;

    /** Maximum length of the city column. */
    private static final int CITY_LENGTH = 128;

    /** Maximum length of the state column. */
    private static final int STATE_LENGTH = 64;

    /** Maximum length of the postal code column. */
    private static final int POSTAL_CODE_LENGTH = 32;

    /** Database primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Patient this snapshot describes. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    /** Source the snapshot came from. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "source_id", nullable = false)
    private EhrSource source;

    /**
     * The source's own identifier for this patient, for example a FHIR {@code Patient.id}.
     * This is the crosswalk: a date-of-birth mismatch may mean the wrong external record was
     * linked here, and this column is what makes that diagnosable.
     */
    @Column(name = "source_patient_id", nullable = false, length = SOURCE_PATIENT_ID_LENGTH)
    private String sourcePatientId;

    /** Given name as reported by the source. */
    @Column(name = "first_name", length = NAME_LENGTH)
    private String firstName;

    /** Family name as reported by the source. */
    @Column(name = "last_name", length = NAME_LENGTH)
    private String lastName;

    /** Date of birth, normalized to a real date at ingest. */
    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;

    /** Contact phone as reported by the source. */
    @Column(name = "phone", length = PHONE_LENGTH)
    private String phone;

    /** Contact email as reported by the source. */
    @Column(name = "email", length = NAME_LENGTH)
    private String email;

    /** First address line as reported by the source. */
    @Column(name = "address_line1", length = NAME_LENGTH)
    private String addressLine1;

    /** Second address line as reported by the source. */
    @Column(name = "address_line2", length = NAME_LENGTH)
    private String addressLine2;

    /** City as reported by the source. */
    @Column(name = "city", length = CITY_LENGTH)
    private String city;

    /** State or region as reported by the source. */
    @Column(name = "state", length = STATE_LENGTH)
    private String state;

    /** Postal code as reported by the source. */
    @Column(name = "postal_code", length = POSTAL_CODE_LENGTH)
    private String postalCode;

    /**
     * When the source itself last changed this record, from FHIR {@code meta.lastUpdated}.
     * This — not {@link #fetchedAt} — is what decides recency when the reconciler auto-applies
     * a low-risk field, since polling order says nothing about which value is newer.
     */
    @Column(name = "source_updated_at")
    private LocalDateTime sourceUpdatedAt;

    /** When this snapshot was pulled by the adapter. */
    @Column(name = "fetched_at", nullable = false)
    private LocalDateTime fetchedAt;

    /**
     * Raw resource payload as returned by the source, retained for debugging normalization
     * disputes. Contains PHI and must never be exposed through an unscoped endpoint.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "raw_payload", columnDefinition = "jsonb")
    private Map<String, Object> rawPayload;
}
