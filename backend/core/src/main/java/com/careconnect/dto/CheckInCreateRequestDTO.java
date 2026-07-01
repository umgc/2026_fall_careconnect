package com.careconnect.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public record CheckInCreateRequestDTO(
        @NotNull(message = "patientId must not be null")
        Long patientId,

        @NotEmpty(message = "selectedQuestionIds must not be empty")
        List<@NotNull(message = "selectedQuestionIds must not contain null values") Long> selectedQuestionIds
) {
}
