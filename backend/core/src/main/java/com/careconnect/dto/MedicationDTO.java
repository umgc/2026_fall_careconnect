package com.careconnect.dto;

import com.careconnect.model.Medication.MedicationType;
import lombok.Builder;

import java.time.Instant;

@Builder
public record MedicationDTO(
        Long id,
        Long patientId,
        String medicationName,
        String dosage,
        String frequency,
        String route,
        MedicationType medicationType,
        String prescribedBy,
        String prescribedDate,
        String startDate,
        String endDate,
        String notes,
        Boolean isActive,
        Instant lastTaken
) {
}
