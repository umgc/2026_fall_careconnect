package com.careconnect.model.EHR;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;


@Entity
@Table(name = "ehr_visit_records")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EHRVisitRecord{
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id

    @Column(name = "last_updated", nullable = false)
    private LocalDateTime lastUpdated;

    @Column(name="source_id", nullable=false)
    private String sourceId; // Which EHR source produced this.

    @Column(name="identifier")
    private String identifier;

    @Column(name="care_team")
    private String careTeam;

    @Column(name="accident")
    private String accident;


    @Column(name="created")
    private LocalDateTime created;

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