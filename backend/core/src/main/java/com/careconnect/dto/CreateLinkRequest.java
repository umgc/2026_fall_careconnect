package com.careconnect.dto;

import java.time.LocalDateTime;

public record CreateLinkRequest(
        Long targetUserId,  // Patient ID for caregiver links, Family member ID for family links
        String linkType,    // PERMANENT, TEMPORARY, EMERGENCY
        LocalDateTime expiresAt,  // Optional expiration date for temporary links
        String notes        // Optional notes about the link
) {
}
