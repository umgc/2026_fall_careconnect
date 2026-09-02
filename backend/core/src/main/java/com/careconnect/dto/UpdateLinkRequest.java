package com.careconnect.dto;

import java.time.LocalDateTime;

public record UpdateLinkRequest(
        String status,      // ACTIVE, SUSPENDED, REVOKED
        String linkType,    // PERMANENT, TEMPORARY, EMERGENCY
        LocalDateTime expiresAt,  // Optional expiration date
        String notes        // Optional notes
) {
}
