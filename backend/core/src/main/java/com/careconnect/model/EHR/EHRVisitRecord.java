package com.careconnect.model;

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
class EHRVisitRecord{
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "client_id", nullable = false)
    private Long clientId; // patient.id

    @Column(name = "last_updated", nullable = false)
    private LocalDateTime lastUpdated;

}