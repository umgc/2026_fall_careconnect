package com.careconnect.dto;

import lombok.Builder;

import java.time.Instant;

@Builder
public record VitalSampleDTO(
        Long id,                   // Primary key for updates
        Long patientId,
        Instant timestamp,
        Double heartRate,
        Double spo2,
        Integer systolic,
        Integer diastolic,
        Double weight,
        Integer moodValue,         // 1-10 scale
        Integer painValue          // 1-10 scale
) {
}