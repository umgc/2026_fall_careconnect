package com.careconnect.dto;

import java.time.OffsetDateTime;

public record CheckInSummaryDTO(
        Long checkInId,
        Long patientId,
        OffsetDateTime createdAt,
        OffsetDateTime submittedAt,
        int questionCount
) {
}
