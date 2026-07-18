package com.careconnect.dto;

import java.time.LocalDateTime;

/**
 * Response for invite creation. Includes the raw token + share URL (only place
 * the raw token is ever returned), plus the link type and expiration metadata
 * required by issue #53.
 */
public record CreateInviteResponse(
        Long tokenId,
        String token,          // raw token — share this, it is not stored in plaintext
        String inviteUrl,      // canonical URL the caregiver shares / encodes as QR (#69)
        Long linkId,
        String linkType,
        String status,
        LocalDateTime expiresAt,
        LocalDateTime createdAt
) {}
