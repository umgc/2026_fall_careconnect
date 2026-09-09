package com.careconnect.model.ehr;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hl7.fhir.r4.model.Coverage;

import java.time.LocalDateTime;
import java.util.Date;

@Entity
@Table(name = "ehr_coverage")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EHRCoverage{
    public EHRCoverage(Long clientId, Coverage coverage, LocalDateTime lastUpdated, Long sourceId){
        this.clientId = clientId;
        this.sourceId = sourceId;
        this.lastUpdated = lastUpdated;
        this.identifier = coverage.getId();
        this.beneficiary = coverage.getBeneficiary().getDisplay();
        this.network = coverage.getNetwork();
        this.payor = coverage.getPayorFirstRep().getDisplay();
        this.expires = coverage.getPeriod().getEnd();
        this.status = coverage.getStatus().getDisplay();
        this.subscriberId = coverage.getSubscriberId();
        this.coverage = coverage.getCostToBeneficiaryFirstRep().fhirType();
    }


    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id; // unique ID

    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id

    @Column(name="source_id", nullable=false)
    private long sourceId; // Which EHR.source produced this.

    @Column(name = "last_updated", nullable = false)
    private LocalDateTime lastUpdated;

    @Column(name="identifier")
    private String identifier;

    @Column(name="beneficiary")
    private String beneficiary;

    @Column(name="network")
    private String network;

    @Column(name="payor")
    private String payor;

    @Column(name="expires")
    private Date expires;

    @Column(name="status")
    private String status;

    @Column(name="member_id")
    private String memberId;

    @Column(name="subscriber_id")
    private String subscriberId;

    @Column(name="coverage")
    private String coverage;
    

}