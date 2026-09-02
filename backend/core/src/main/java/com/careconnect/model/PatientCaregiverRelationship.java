package com.careconnect.model;

import jakarta.persistence.*;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import lombok.Builder;

@Entity
@Table(name = "patient_caregiver")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PatientCaregiverRelationship {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id")
    private Long patientId;

    @Column(name = "caregiver_user_id")
    private Long caregiverUserId;

    @Column(name = "relationship_type")
    private String relationshipType; // PRIMARY, SECONDARY, 
}