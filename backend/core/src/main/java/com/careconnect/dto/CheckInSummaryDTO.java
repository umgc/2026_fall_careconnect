package com.careconnect.dto;

import java.time.OffsetDateTime;

public record CheckInSummaryDTO(
        Long checkInId,
        Long patientId,
        OffsetDateTime createdAt,
        OffsetDateTime submittedAt,
        OffsetDateTime reviewedAt,
        int questionCount
) {
    public CheckInSummaryDTO(
            Long checkInId,
            Long patientId,
            OffsetDateTime createdAt,
            OffsetDateTime submittedAt,
            int questionCount
    ) {
        this(checkInId, patientId, createdAt, submittedAt, null, questionCount);
    }
}
