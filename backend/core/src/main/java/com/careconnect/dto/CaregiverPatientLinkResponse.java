package com.careconnect.dto;

import java.time.LocalDateTime;

public record CaregiverPatientLinkResponse(
        Long id,
        Long caregiverUserId,
        String caregiverName,
        String caregiverEmail,
        Long patientUserId,
        String patientName,
        String patientEmail,
        String status,
        String linkType,
        boolean patientVideoCallsEnabled,
        boolean patientMessagingEnabled,
        LocalDateTime createdAt,
        LocalDateTime expiresAt,
        String notes,
        String createdBy,
        boolean isActive,
        boolean isExpired
) {
}
