package com.careconnect.dto;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public record CheckInAnswerDetailDTO(
        Long questionId,
        String prompt,
        String type,
        boolean required,
        int ordinal,
        String valueText,
        Boolean valueBoolean,
        BigDecimal valueNumber,
        OffsetDateTime answeredAt
) {
}
