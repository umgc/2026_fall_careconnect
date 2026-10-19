package com.careconnect.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.Builder;

import java.time.Instant;
import java.util.List;

@Builder
public record DashboardDTO(
        Instant periodStart,
        Instant periodEnd,
        double adherenceRate,
        double avgHeartRate,
        Double avgSpo2,            // nullable
        Double avgSystolic,
        Double avgDiastolic,
        Double avgWeight,
        Double avgMood,            // 1-10 scale
        Double avgPain,            // 1-10 scale
        Integer moodEntries,       // number of mood entries in period
        Integer painEntries        // number of pain entries in period
) {
}