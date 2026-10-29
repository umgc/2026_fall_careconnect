package com.careconnect.dto;

import java.time.Instant;

/**
 * Request body for granting EHR_VIEW consent from the authenticated patient to a caregiver,
 * letting that caregiver read the patient's EHR records via the generic {@code /api/ehr} surface.
 *
 * @param granteeUserId user id of the caregiver receiving consent (required)
 * @param granteeRole   optional role label; defaults to {@code CAREGIVER}
 * @param expiresAt     optional expiry; null means no expiry
 */
public record EhrViewConsentRequest(
        Long granteeUserId,
        String granteeRole,
        Instant expiresAt
) {
}
