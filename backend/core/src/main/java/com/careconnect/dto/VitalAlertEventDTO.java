package com.careconnect.dto;

import java.time.Instant;

public record VitalAlertEventDTO(
        Long id,
        Long patientId,
        Long patientUserId,
        String metricType,
        String measuredValue,
        String alertLevel,
        String status,
        Integer recipientCount,
        Integer successCount,
        Integer failureCount,
        String failureReason,
        Instant occurredAt
) {
}
