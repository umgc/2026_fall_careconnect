package com.careconnect.dto;

import lombok.Builder;

import java.time.Instant;

@Builder
public record SymptomEntryDTO(
        Long id,
        Long patientId,
        String symptomKey,
        String symptomValue,
        Integer severity,
        Boolean completed,
        Instant takenAt
) {
}
