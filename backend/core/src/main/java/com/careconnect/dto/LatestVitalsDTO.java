package com.careconnect.dto;

import lombok.Builder;

import java.time.Instant;

@Builder
public record LatestVitalsDTO(
        Long id,
        Instant timestamp,
        Double heartRate,
        Double spo2,
        Integer systolic,
        Integer diastolic,
        Double weight,
        Integer moodValue,
        Integer painValue,
        Instant createdAt
) {
}
