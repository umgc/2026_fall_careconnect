package com.careconnect.dto;

import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;

import java.time.Instant;

/**
 * API view of one CR-2 Medicare share: a {@code MEDICARE_VIEW} grant held by a
 * {@code SHARE_RECIPIENT}.
 *
 * @param id              grant id
 * @param patientUserId   patient who shared
 * @param recipientUserId registered user the records were shared with
 * @param recipientEmail  recipient's email
 * @param recipientName   recipient's display name, if known
 * @param scope           always {@code MEDICARE_VIEW}
 * @param status          {@code ACTIVE} or {@code REVOKED}
 * @param grantedAt       when the share started
 * @param expiresAt       when the share ends (90 days after it started)
 * @param emailSent       whether the notice email was sent; null when listing existing shares
 */
public record MedicareShareResponse(
        Long id,
        Long patientUserId,
        Long recipientUserId,
        String recipientEmail,
        String recipientName,
        String scope,
        String status,
        Instant grantedAt,
        Instant expiresAt,
        Boolean emailSent
) {
    public static MedicareShareResponse from(
            final ConsentGrant grant, final User recipient, final Boolean emailSent) {
        return new MedicareShareResponse(
                grant.getId(),
                grant.getPatientUserId(),
                grant.getGranteeUserId(),
                recipient == null ? null : recipient.getEmail(),
                recipient == null ? null : recipient.getName(),
                grant.getScope(),
                grant.getStatus(),
                grant.getGrantedAt(),
                grant.getExpiresAt(),
                emailSent);
    }
}
