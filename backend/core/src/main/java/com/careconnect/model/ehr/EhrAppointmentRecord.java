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
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * One appointment as reported by a source, per {@code EHR_Canonical_Schema_Draft.md}. Serves as
 * the first canonical (non-identity) table implemented from that draft — coverage and visit
 * records follow the same shape later, owned by whichever team needs them next.
 *
 * <p>Keyed by {@code (patient_id, source_id, external_appointment_id)}, not {@code (patient_id)}
 * alone, so two sources reporting the same appointment never collide into one row.
 *
 * <p>{@link #status} is a plain string, not a Java enum: the draft flags athenahealth's actual FHIR
 * {@code Appointment} status vocabulary as unverified, and a source can return a value CareConnect
 * has not modeled yet. An {@code @Enumerated} field would make Hibernate emit a check constraint
 * that fails the whole sync the first time that happens; the source owns this value set, not us.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "ehr_appointment_record")
public class EhrAppointmentRecord extends Auditable {

    /** Maximum length of the source's own appointment identifier. */
    private static final int EXTERNAL_APPOINTMENT_ID_LENGTH = 128;

    /** Maximum length of the status column. */
    private static final int STATUS_LENGTH = 32;

    /** Maximum length of name/location/service/reason columns. */
    private static final int TEXT_LENGTH = 255;

    /** Database primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Patient this appointment belongs to. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    /** Source the appointment was fetched from. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "source_id", nullable = false)
    private EhrSource source;

    /** Raw FHIR {@code Appointment} resource this row was mapped from, if retained. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "raw_payload_id")
    private EhrRawPayload rawPayload;

    /** The source's own identifier for this appointment, for example a FHIR {@code Appointment.id}. */
    @Column(name = "external_appointment_id", nullable = false, length = EXTERNAL_APPOINTMENT_ID_LENGTH)
    private String externalAppointmentId;

    /** Scheduled start time. */
    @Column(name = "start_time")
    private LocalDateTime startTime;

    /** Scheduled end time. */
    @Column(name = "end_time")
    private LocalDateTime endTime;

    /**
     * Lifecycle status as reported by the source, for example {@code booked}, {@code arrived},
     * {@code fulfilled}, {@code cancelled}, or {@code noshow}. Provisional per the draft; not
     * validated against a fixed vocabulary here.
     */
    @Column(name = "status", length = STATUS_LENGTH)
    private String status;

    /** Provider name as reported by the source. */
    @Column(name = "provider_name", length = TEXT_LENGTH)
    private String providerName;

    /** Location name or description as reported by the source. */
    @Column(name = "location", length = TEXT_LENGTH)
    private String location;

    /** Type of service for this appointment, as reported by the source. */
    @Column(name = "service_type", length = TEXT_LENGTH)
    private String serviceType;

    /** Reason for the appointment, as reported by the source. */
    @Column(name = "reason", length = TEXT_LENGTH)
    private String reason;

    /** When the source created this appointment, from FHIR {@code Appointment.created}. */
    @Column(name = "source_created_at")
    private LocalDateTime sourceCreatedAt;

    /** When the source last updated this appointment, from FHIR {@code meta.lastUpdated}. */
    @Column(name = "source_updated_at")
    private LocalDateTime sourceUpdatedAt;
}
