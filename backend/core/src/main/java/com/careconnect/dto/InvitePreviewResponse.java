package com.careconnect.dto;

import java.time.LocalDateTime;

/**
 * Stable, non-enumerating preview returned by GET /v1/api/invite/{token}.
 * <p>
 * Issues #59 + #81:
 * - "Who Invited Me?" context: inviterName, patientName, inviteReason.
 * - The structure is STABLE: the same fields are returned for valid AND
 * invalid/expired/revoked tokens. For non-valid tokens the context fields
 * are null and {@code valid=false}, so the endpoint never reveals via HTTP
 * status whether a token merely doesn't exist vs. exists-but-expired.
 * - {@code status} is one of VALID | EXPIRED | REVOKED | ACCEPTED | INVALID.
 * - {@code nextAction} tells the frontend what to do next (ACCEPT, REQUEST_NEW,
 * SIGN_IN, NONE) so onboarding logic doesn't branch on status text.
 * <p>
 * To avoid enumeration, EXPIRED/REVOKED/ACCEPTED/INVALID are collapsed at the
 * HTTP layer into a single 200 response with this body. Only {@code status}
 * distinguishes them, and only AFTER the raw token hash has been verified, so
 * an attacker without the real token cannot tell these apart.
 */
public record InvitePreviewResponse(
        boolean valid,
        String status,         // VALID | EXPIRED | REVOKED | ACCEPTED | INVALID
        String nextAction,     // ACCEPT | REQUEST_NEW | SIGN_IN | NONE
        Long linkId,
        String linkType,
        String inviterName,
        String patientName,
        String inviteReason,
        String invitedEmail,
        LocalDateTime expiresAt
) {

    /**
     * Convenience factory for a fully-populated, valid preview.
     */
    public static InvitePreviewResponse valid(Long linkId, String linkType, String inviterName,
                                              String patientName, String inviteReason,
                                              String invitedEmail, LocalDateTime expiresAt,
                                              boolean requiresSignIn) {
        return new InvitePreviewResponse(
                true,
                "VALID",
                requiresSignIn ? "SIGN_IN" : "ACCEPT",
                linkId, linkType, inviterName, patientName, inviteReason, invitedEmail, expiresAt);
    }

    /**
     * Non-enumerating factory for any non-valid token. Context fields are null
     * so nothing about the care circle or inviter leaks.
     *
     * @param status     EXPIRED | REVOKED | ACCEPTED | INVALID
     * @param nextAction REQUEST_NEW | SIGN_IN | NONE
     */
    public static InvitePreviewResponse notValid(String status, String nextAction) {
        return new InvitePreviewResponse(
                false, status, nextAction,
                null, null, null, null, null, null, null);
    }
}
