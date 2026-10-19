package com.careconnect.repository;

import org.springframework.data.jpa.repository.*;
import org.springframework.stereotype.Repository;

import com.careconnect.model.SummaryMetric;

import java.time.Instant;

@Repository
public interface SummaryMetricRepository extends JpaRepository<SummaryMetric, Long> {
    SummaryMetric findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
            Long patientId, Instant periodStart, Instant periodEnd
    );
}
