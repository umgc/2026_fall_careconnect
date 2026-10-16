package com.careconnect.dto;

import java.time.Instant;

/**
 * Request body for granting or revoking Medicare View ({@code MEDICARE_VIEW}) consent from the
 * authenticated patient to a caregiver linked to them.
 *
 * @param granteeUserId user id of the caregiver receiving consent (required)
 * @param granteeRole   optional; when present it must be {@code CAREGIVER}
 * @param expiresAt     optional expiry, which must be in the future; null means no expiry
 */
public record MedicareViewConsentRequest(
        Long granteeUserId,
        String granteeRole,
        Instant expiresAt
) {
}
