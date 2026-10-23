package com.careconnect.dto;

import com.careconnect.model.ConsentGrant;

import java.time.Instant;

/**
 * API view of a {@link ConsentGrant} for Medicare View consent.
 *
 * @param id            grant id
 * @param patientUserId patient who granted consent
 * @param granteeUserId caregiver who received consent
 * @param granteeRole   role label recorded on the grant
 * @param scope         consent scope (always {@code MEDICARE_VIEW} for this API)
 * @param status        {@code ACTIVE} or {@code REVOKED}
 * @param grantedAt     when the grant became active
 * @param expiresAt     optional expiry
 * @param revokedAt     when revoked, if applicable
 */
public record MedicareViewConsentResponse(
        Long id,
        Long patientUserId,
        Long granteeUserId,
        String granteeRole,
        String scope,
        String status,
        Instant grantedAt,
        Instant expiresAt,
        Instant revokedAt
) {
    public static MedicareViewConsentResponse from(final ConsentGrant grant) {
        return new MedicareViewConsentResponse(
                grant.getId(),
                grant.getPatientUserId(),
                grant.getGranteeUserId(),
                grant.getGranteeRole(),
                grant.getScope(),
                grant.getStatus(),
                grant.getGrantedAt(),
                grant.getExpiresAt(),
                grant.getRevokedAt());
    }
}
