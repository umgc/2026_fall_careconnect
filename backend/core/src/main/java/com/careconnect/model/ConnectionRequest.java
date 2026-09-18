package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(name = "connection_requests")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ConnectionRequest {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "caregiver_id")
    private User caregiver;

    @ManyToOne
    @JoinColumn(name = "patient_id")
    private User patient;

    @Column(nullable = false)
    private String status; // PENDING, ACCEPTED, REJECTED

    private String relationshipType;
    private String message;

    private Instant requestedAt;
    private Instant respondedAt;

    private String token;
}