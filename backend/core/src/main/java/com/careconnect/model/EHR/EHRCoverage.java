package com.careconnect.model.EHR;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "ehr_coverage")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EHRCoverage{
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id; // unique ID

    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id

    @Column(name="source_id", nullable=false)
    private String sourceId; // Which EHR source produced this.

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
    private LocalDateTime expires;

    @Column(name="status")
    private String status;

    @Column(name="subscriber_id")
    private String subscriberId;

    @Column(name="coverage")
    private String coverage;
    

}