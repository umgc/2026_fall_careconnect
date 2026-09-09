package com.careconnect.model.ehr;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.Date;

import org.hl7.fhir.r4.model.Patient;

@Entity
@Table(name = "ehr_identities")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EHRIdentity{
    public EHRIdentity(Long clientId, Patient patient, LocalDateTime lastUpdated, Long sourceId){
        this.clientId = clientId;
        this.sourceId = sourceId;
        this.lastUpdated = lastUpdated;
        this.identifier = patient.getId();
        this.name = patient.getNameFirstRep().getText();
        this.gender = patient.getGender().getDisplay();
        this.active = patient.getActive();
        this.dob = patient.getBirthDate();
        this.deceased = patient.getDeceasedBooleanType().booleanValue();
        this.dod = patient.getDeceasedDateTimeType().getValue();
        this.address = patient.getAddressFirstRep().getText();
        this.managingOrg = patient.getManagingOrganization().getDisplay();
        this.phone_number = patient.getTelecomFirstRep().toString();
        this.marital_status = patient.getMaritalStatus().getText();
        this.language = patient.getCommunicationFirstRep().getLanguage().getText();
        this.provider = patient.getGeneralPractitionerFirstRep().getDisplay();
        this.photo = patient.getPhotoFirstRep().getUrl();
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id; // unique ID

    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id

    @Column(name="source_id", nullable=false)
    private Long sourceId; // Which EHR.source produced this.

    @Column(name = "last_updated", nullable = false)
    private LocalDateTime lastUpdated; // When was last checked.

    @Column(name="identifier")
    private String identifier;

    @Column(name="name")
    private String name;

    @Column(name="gender")
    private String gender;

    @Column(name="active")
    private boolean active;

    @Column(name="dob")
    private Date dob;

    @Column(name="deceased")
    private boolean deceased;

    @Column(name="dod")
    private Date dod;

    @Column(name="address")
    private String address;

    @Column(name="managing_org")
    private String managingOrg;

    @Column(name="phone_number")
    private String phone_number;

    @Column(name="email")
    private String email;

    @Column(name="marital_status")
    private String marital_status;

    @Column(name="language")
    private String language; // Name of primary language

    @Column(name="provider")
    private String provider;

    @Column(name="photo")
    private String photo; // Photo url

}