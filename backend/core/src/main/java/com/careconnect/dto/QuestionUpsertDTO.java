package com.careconnect.dto;

import com.careconnect.model.QuestionType;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record QuestionUpsertDTO(
        @NotBlank(message = "prompt must not be blank")
        String prompt,

        @NotNull(message = "type must not be null")
        QuestionType type,

        boolean required,

        @NotNull(message = "ordinal must not be null")
        @Min(value = 0, message = "ordinal must be 0 or greater")
        Integer ordinal
) { }