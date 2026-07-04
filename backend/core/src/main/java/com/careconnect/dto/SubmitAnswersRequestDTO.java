package com.careconnect.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public record SubmitAnswersRequestDTO(
        @NotEmpty(message = "answers must not be empty")
        List<@Valid @NotNull(message = "answer elements must not be null") AnswerUpsertRequestDTO> answers
) {
}
