package com.careconnect.dto;

import java.math.BigDecimal;

public record QuestionDTO(
        Long id,
        String prompt,
        String type,
        boolean required,
        boolean active,
        int ordinal,
        String formKey,
        int formVersion,
        String sectionKey,
        String fieldKey,
        BigDecimal scoreWeight
) {
    public QuestionDTO(Long id, String prompt, String type, boolean required, boolean active, int ordinal) {
        this(id, prompt, type, required, active, ordinal, "virtual-checkin", 1, "general", "question_field", null);
    }
}
