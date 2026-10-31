package com.careconnect.dto.ehr;

/**
 * Request body for {@code POST /v1/api/ehr/identity-conflicts/{id}/resolve}.
 *
 * @param status     the patient's decision: {@code ACCEPTED} to apply the incoming value or
 *                   {@code REJECTED} to keep the existing one. Required.
 * @param resolvedBy informational only — the reconciler always records {@code PATIENT} (the single
 *                   resolver for {@code date_of_birth}); accepted but never branched on.
 */
public record EhrIdentityConflictResolveRequest(String status, String resolvedBy) {
}
