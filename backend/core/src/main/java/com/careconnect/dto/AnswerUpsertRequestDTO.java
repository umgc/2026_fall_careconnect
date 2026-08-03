package com.careconnect.dto;

import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

public record AnswerUpsertRequestDTO(
        @NotNull(message = "questionId must not be null")
        Long questionId,
        String valueText,
        Boolean valueBoolean,
        BigDecimal valueNumber
) {
}
