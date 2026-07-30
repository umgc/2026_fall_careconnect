package com.careconnect.dto;

import java.time.OffsetDateTime;

public record SubmitAnswersResponseDTO(
        Long checkInId,
        int acceptedAnswerCount,
        OffsetDateTime submittedAt
) {
}
