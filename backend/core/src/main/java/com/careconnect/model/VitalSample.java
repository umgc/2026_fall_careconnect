package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;

@Entity
@Table(name = "vital_sample")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class VitalSample {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;
    
    @Column(name = "timestamp", nullable = false)
    private Instant timestamp;
    
    @Column(name = "heart_rate")
    private Double heartRate;
    
    @Column(name = "spo2")
    private Double spo2;
    
    @Column(name = "systolic")
    private Integer systolic;
    
    @Column(name = "diastolic")
    private Integer diastolic;
    
    @Column(name = "weight")
    private Double weight;
    
    @Column(name = "mood_value")
    private Integer moodValue; // 1-10 scale
    
    @Column(name = "pain_value")
    private Integer painValue; // 1-10 scale

    @Column(name = "source", length = 64)
    private String source;
    
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
    
    @Column(name = "updated_at")
    private Instant updatedAt;
    
    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        this.createdAt = now;
        this.updatedAt = now;
    }
    
    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = Instant.now();
    }
}
