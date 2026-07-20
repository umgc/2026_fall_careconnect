package com.careconnect.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * One ranked match from the natural-language mail search API (Task 3.14.7 / #124).
 */
public record NaturalLanguageMailSearchMatch(
        Long mailpieceId,
        String sender,
        String summary,
        String imageRef,
        LocalDate digestDate,
        OffsetDateTime receivedAt,
        String importanceLevel,
        String importanceCategory,
        String importanceReasoning,
        double score,
        String snippet,
        List<String> matchSources
) {
}
