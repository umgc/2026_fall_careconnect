package com.careconnect.dto;

/**
 * Returned after a successful POST /v1/api/invite/{token}/accept.
 * Provides the handoff payload for the registration/join flow (issue #75).
 */
public record AcceptInviteResponse(
        Long linkId,
        String linkType,
        Long patientUserId,
        String patientName,
        String message
) {}
