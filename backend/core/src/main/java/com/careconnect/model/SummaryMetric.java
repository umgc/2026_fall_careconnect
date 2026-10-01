package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(
        name = "summary_metrics",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_patient_window",
                columnNames = {"patient_user_id", "period_start", "period_end"}
        )
)
@Data
@EqualsAndHashCode(callSuper = false)
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SummaryMetric extends Auditable {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_user_id", nullable = false)
    private Patient patient;

    @Column(name = "period_start", nullable = false)
    private Instant periodStart;

    @Column(name = "period_end", nullable = false)
    private Instant periodEnd;

    @Column(name = "adherence_rate")
    private Double adherenceRate;

    @Column(name = "avg_heart_rate")
    private Double avgHeartRate;

    // createdAt and updatedAt are inherited from Auditable

    public Instant getGeneratedAt() {
        return getGeneratedAt();
    }
}