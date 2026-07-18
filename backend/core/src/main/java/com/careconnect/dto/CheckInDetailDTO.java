package com.careconnect.dto;

import java.time.OffsetDateTime;
import java.util.List;

public record CheckInDetailDTO(
        Long checkInId,
        Long patientId,
        OffsetDateTime createdAt,
        OffsetDateTime submittedAt,
        OffsetDateTime reviewedAt,
        String status,
        List<CheckInAnswerDetailDTO> answers
) {
}
