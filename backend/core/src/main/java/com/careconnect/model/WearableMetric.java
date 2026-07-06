package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(name = "wearable_metric")
@EqualsAndHashCode(callSuper = false)
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class WearableMetric extends Auditable {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

   @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_user_id")
    private User patient;

    @Enumerated(EnumType.STRING)
    private MetricType metric;

    @Column(name = "metric_value", nullable = false)   
    private Double metricValue;                       

    @Column(name = "recorded_at", nullable = false)
    private Instant recordedAt;

    /**
     * Supported persisted metric types in the wearable_metric table.
     * Blood pressure is persisted as two rows (systolic/diastolic).
     */
    public enum MetricType {
        HEART_RATE,
        SPO2,
        TEMPERATURE,
        BLOOD_PRESSURE_SYS,
        BLOOD_PRESSURE_DIA,
        WEIGHT,
        STEPS
    }
}