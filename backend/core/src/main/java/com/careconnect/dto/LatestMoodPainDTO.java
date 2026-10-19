package com.careconnect.dto;

import lombok.Builder;

import java.time.LocalDateTime;

@Builder
public record LatestMoodPainDTO(
        Long id,
        Integer moodValue,
        Integer painValue,
        String note,
        LocalDateTime timestamp,
        LocalDateTime createdAt
) {
}
