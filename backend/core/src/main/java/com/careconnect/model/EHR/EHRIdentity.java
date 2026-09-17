package com.careconnect.model.EHR;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;


@Entity
@Table(name = "ehr_identities")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EHRIdentity{
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

    @Column(name="member_id")
    private String memberId;

    @Column(name="name")
    private String name;

    @Column(name="gender")
    private String gender;

    @Column(name="active")
    private boolean active;

    @Column(name="dob")
    private LocalDateTime dob;

    @Column(name="deceased")
    private boolean deceased;

    @Column(name="dod")
    private LocalDateTime dod;

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
    private String photo; // Photo encoded in base64

}