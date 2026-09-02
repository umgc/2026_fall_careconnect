package com.careconnect.dto;

import lombok.Builder;

import java.time.Instant;

@Builder
public record SymptomDTO(
        Long id,
        Long patientId,
        String symptomKey,      // e.g. "anxiety", "headache"
        String symptomValue,    // e.g. "panic attack", "fever 38.5"
        Integer severity,       // 1..5  (map Mild=1, Moderate=3, Severe=5)
        Boolean completed,
        Instant takenAt,
        String notes            // Clinical notes
) {
}
