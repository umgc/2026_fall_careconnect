package com.careconnect.dto;

import java.time.LocalDateTime;

/**
 * Sanitised preview returned by GET /v1/api/invite/{token}.
 *
 * Issue #53: surfaces the link type, status, and expiration metadata for an
 * invite token without leaking the token hash or internal IDs of unrelated
 * users. (The richer "Who Invited Me?" context and non-enumerating behaviour
 * are layered on in issue #59.)
 */
public record InvitePreviewResponse(
        Long linkId,
        String linkType,
        String status,
        String inviterName,
        String patientName,
        String inviteReason,
        String invitedEmail,
        LocalDateTime expiresAt
) {}
