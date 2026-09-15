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
 * One raw FHIR resource as fetched from a source, kept independent of any canonical row.
 *
 * <p>Every canonical table (this branch starts with {@link EhrAppointmentRecord}) points here
 * through a nullable {@code raw_payload_id} rather than embedding its own payload column. That
 * separation lets an adapter persist what it fetched before mapping succeeds — a raw payload
 * with no canonical row attached yet is diagnosable and re-mappable, whereas a payload column
 * inlined on the canonical row only exists once every required mapped field is also present.
 *
 * <p>Contains PHI and must never be exposed through an unscoped endpoint.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "ehr_raw_payload")
public class EhrRawPayload extends Auditable {

    /** Maximum length of the FHIR resource type name. */
    private static final int RESOURCE_TYPE_LENGTH = 64;

    /** Maximum length of the source's own identifier for the fetched resource. */
    private static final int EXTERNAL_RESOURCE_ID_LENGTH = 128;

    /** Database primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Patient this payload was fetched for. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    /** Source the payload was fetched from. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "source_id", nullable = false)
    private EhrSource source;

    /**
     * The FHIR resource type of the payload, for example {@code Appointment}, {@code Patient},
     * {@code Coverage}, or {@code ExplanationOfBenefit}. One shared table serves every resource
     * type rather than one raw table per canonical table.
     */
    @Column(name = "resource_type", nullable = false, length = RESOURCE_TYPE_LENGTH)
    private String resourceType;

    /** The source's own id for this resource, for example a FHIR {@code Appointment.id}. */
    @Column(name = "external_resource_id", nullable = false, length = EXTERNAL_RESOURCE_ID_LENGTH)
    private String externalResourceId;

    /** Raw FHIR resource as returned by the source. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> payload;

    /**
     * Size of the serialized payload in bytes, recorded so oversized rows (for example an
     * embedded {@code Patient.photo}) can be found later. No cap is enforced here yet — the cap
     * value and whether stripping happens before or after insert remain open questions.
     */
    @Column(name = "payload_size_bytes", nullable = false)
    private int payloadSizeBytes;

    /** When the adapter fetched this payload. */
    @Column(name = "fetched_at", nullable = false)
    private LocalDateTime fetchedAt;
}
