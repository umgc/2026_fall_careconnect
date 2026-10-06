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
import org.hl7.fhir.r4.model.ExplanationOfBenefit;

import java.time.Instant;
import java.time.LocalDateTime;

/**
 * One visit or claim as reported by a single source — a mapped FHIR
 * {@code ExplanationOfBenefit} or equivalent.
 * <p>
 * Table renamed from {@code ehr_visit_records} to the singular {@code ehr_visit_record}: every
 * other table in this schema is singular ({@code patient}, {@code caregiver},
 * {@code ehr_source}, {@code ehr_audit_event}), and under {@code ddl-auto=update} a second
 * spelling means a second table rather than a rename.
 * <p>
 * <strong>Single-source persistence only.</strong> Cross-source reconciliation of visits is
 * explicitly out of scope here (§3.2): FR-XSRC-03/04 require two records to be flagged with a
 * delta rather than merged unless they agree on provider, service date and patient identity,
 * and nothing in this table or the identity-reconciliation design implements that. Rows from
 * different sources describing the same real visit will sit side by side until that is
 * designed.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_visit_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_visit_record_source_external",
                columnNames = {"patient_id", "source_id", "external_visit_id"}),
        indexes = {
                @Index(name = "idx_ehr_visit_record_patient", columnList = "patient_id"),
                @Index(name = "idx_ehr_visit_record_service_date", columnList = "service_date")
        })
public class EhrVisitRecord extends Auditable {
    public EhrVisitRecord(Long patientId, ExplanationOfBenefit eob, Long sourceId){
        this.patientId = patientId;
        this.sourceUpdatedAt = eob.getMeta().getLastUpdated().toInstant();
        this.sourceId = sourceId;
        this.externalVisitId = eob.getId();
        this.careTeam = eob.getCareTeamFirstRep().getProvider().getDisplay();
        this.accident = eob.getAccident().getType().getText();
        this.serviceDate = eob.getCreated().toInstant();
        this.diagnosis = eob.getDiagnosisFirstRep().getType().toString();
        this.disposition = eob.getDisposition();
        this.facility = eob.getFacility().getDisplay();
        this.prescription = eob.getPrescription().getDisplay();
        this.procedurePerformed = eob.getProcedureFirstRep().toString();
        this.notes = eob.getProcessNoteFirstRep().getText();
        this.referral = eob.getReferral().getDisplay();
        this.status = eob.getStatus().getDisplay();
        this.visitType = eob.getType().getText();
    }
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Was {@code client_id}. */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}; was a free-text source name. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /** The resource's own id within that source. */
    @Column(name = "external_visit_id", length = 255)
    private String externalVisitId;

    /** Source's last-modified time. Instant, for cross-source comparison. */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    /** When the care happened — the field FR-XSRC-04 matches on, alongside provider and
     *  patient identity. Was named {@code created}, which read as a row-creation timestamp. */
    @Column(name = "service_date")
    private Instant serviceDate;

    @Column(name = "facility", length = 255)
    private String facility;

    @Column(name = "care_team", columnDefinition = "TEXT")
    private String careTeam;

    /**
     * Diagnosis as coded by the source. Left as the source's own text/codes: translating codes
     * to plain language is tracked separately (Draft 1 #2) and is not this table's job.
     */
    @Column(name = "diagnosis", columnDefinition = "TEXT")
    private String diagnosis;

    @Column(name = "procedure_performed", columnDefinition = "TEXT")
    private String procedurePerformed;

    @Column(name = "prescription", columnDefinition = "TEXT")
    private String prescription;

    @Column(name = "disposition", length = 255)
    private String disposition;

    @Column(name = "referral", length = 255)
    private String referral;

    @Column(name = "accident", length = 255)
    private String accident;

    /** FHIR status, e.g. active, cancelled, entered-in-error. Same open question as Coverage. */
    @Column(name = "status", length = 32)
    private String status;

    @Column(name = "visit_type", length = 64)
    private String visitType;

    @Column(name = "notes", columnDefinition = "TEXT")
    private String notes;
}
