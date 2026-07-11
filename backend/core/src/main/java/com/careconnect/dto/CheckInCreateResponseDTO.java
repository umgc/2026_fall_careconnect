package com.careconnect.dto;

import java.time.OffsetDateTime;

public record CheckInCreateResponseDTO(
        Long checkInId,
        Long patientId,
        OffsetDateTime createdAt,
        int questionCount
) {
}
