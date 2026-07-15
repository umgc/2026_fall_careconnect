package com.careconnect.dto;

/**
 * Request body for POST /v1/api/link-management/care-circle/{linkId}/invite
 *
 * @param invitedEmail optional; if set, the accept flow requires the redeemer's
 *                     authenticated email to match (prevents ambiguous sharing).
 * @param inviteReason optional human-readable reason shown by "Who invited me?" (#59).
 * @param ttlHours     optional; null/<=0 falls back to the server default (72h),
 *                     capped at the server max (168h).
 */
public record CreateInviteRequest(
        String invitedEmail,
        String inviteReason,
        Integer ttlHours
) {}
