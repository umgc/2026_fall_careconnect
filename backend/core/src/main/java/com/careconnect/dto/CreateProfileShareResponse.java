package com.careconnect.dto;

import java.time.LocalDateTime;

/**
 * Response for profile-share creation. Includes the raw opaque token + share URL
 * (only place the raw token is returned). Never includes patient id in the URL.
 */
public record CreateProfileShareResponse(
        Long tokenId,
        String token,
        String shareUrl,
        String status,
        LocalDateTime expiresAt,
        LocalDateTime createdAt
) {}
