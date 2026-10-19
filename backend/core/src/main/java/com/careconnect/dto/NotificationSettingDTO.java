package com.careconnect.dto;

import lombok.Builder;

import java.time.Instant;

@Builder
public record NotificationSettingDTO(
        Long id,
        Long userId,
        boolean gamification,
        boolean emergency,
        boolean videoCall,
        boolean audioCall,
        boolean sms,
        boolean significantVitals,
        Instant createdAt,
        Instant updatedAt
) {
}
