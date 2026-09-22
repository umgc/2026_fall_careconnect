package com.careconnect.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.Builder;

import java.time.Instant;
import java.util.List;

@Builder


public record PlanDTO(
        String id,
        boolean active,
        int amount,
        String currency,
        String interval,
        int intervalCount,
        String product,
        String nickname
) {
}