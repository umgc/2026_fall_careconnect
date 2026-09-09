package com.careconnect.model.ehr;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.Date;

import org.hl7.fhir.r4.model.ExplanationOfBenefit;

@Entity
@Table(name = "ehr_visit_records")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EHRVisitRecord{
    public EHRVisitRecord(Long clientId, ExplanationOfBenefit eob, LocalDateTime lastUpdated, Long sourceId){
        this.clientId = clientId;
        this.lastUpdated = lastUpdated;
        this.sourceId = sourceId;
        this.identifier = eob.getId();
        this.careTeam = eob.getCareTeamFirstRep().getProvider().getDisplay();
        this.accident = eob.getAccident().getType().getText();
        this.created = eob.getCreated();
        this.diagnosis = eob.getDiagnosisFirstRep().getType().toString();
        this.disposition = eob.getDisposition();
        this.facility = eob.getFacility().getDisplay();
        this.prescription = eob.getPrescription().getDisplay();
        this.procedure = eob.getProcedureFirstRep().toString();
        this.notes = eob.getProcessNoteFirstRep().getText();
        this.referral = eob.getReferral().getDisplay();
        this.status = eob.getStatus().getDisplay();
        this.type = eob.getType().getText();
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id

    @Column(name = "last_updated", nullable = false)
    private LocalDateTime lastUpdated;

    @Column(name="source_id", nullable=false)
    private Long sourceId; // Which EHR.source produced this.

    @Column(name="identifier")
    private String identifier;

    @Column(name="care_team")
    private String careTeam;

    @Column(name="accident")
    private String accident;


    @Column(name="created")
    private Date created;

    @Column(name="diagnosis")
    private String diagnosis;

    @Column(name="disposition")
    private String disposition;

    @Column(name="facility")
    private String facility;

    @Column(name="prescription")
    private String prescription;

    @Column(name="procedure")
    private String procedure;

    @Column(name="notes")
    private String notes;

    @Column(name="referral")
    private String referral;

    @Column(name="status")
    private String status;

    @Column(name="type")
    private String type;


}