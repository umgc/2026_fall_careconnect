package com.careconnect.dto;

import com.careconnect.model.QuestionType;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

public record QuestionUpsertDTO(
        @NotBlank(message = "prompt must not be blank")
        String prompt,

        @NotNull(message = "type must not be null")
        QuestionType type,

        boolean required,

        @NotNull(message = "ordinal must not be null")
        @Min(value = 0, message = "ordinal must be 0 or greater")
        Integer ordinal,

        @Size(max = 64, message = "formKey must be at most 64 characters")
        String formKey,

        @Min(value = 1, message = "formVersion must be 1 or greater")
        Integer formVersion,

        @Size(max = 64, message = "sectionKey must be at most 64 characters")
        String sectionKey,

        @Size(max = 128, message = "fieldKey must be at most 128 characters")
        String fieldKey,

        @PositiveOrZero(message = "scoreWeight must be 0 or greater")
        Double scoreWeight
) {
    public QuestionUpsertDTO(String prompt, QuestionType type, boolean required, Integer ordinal) {
        this(prompt, type, required, ordinal, null, null, null, null, null);
    }
}