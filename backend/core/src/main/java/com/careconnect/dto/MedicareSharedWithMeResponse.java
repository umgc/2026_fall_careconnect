package com.careconnect.dto;

import java.time.Instant;

/**
 * One entry in a CR-2 recipient's "Shared with me" list: a patient who shared their Medicare
 * records with the caller, read-only, until {@code expiresAt}.
 *
 * @param shareId       the share's grant id
 * @param patientUserId the sharing patient's user id
 * @param patientId     the sharing patient's {@code patient} record id, which the Medicare reads
 *                      take as {@code ?patientId=}; null if that patient has no record
 * @param patientName   the sharing patient's display name, if known
 * @param grantedAt     when the share started
 * @param expiresAt     when the share ends
 */
public record MedicareSharedWithMeResponse(
        Long shareId,
        Long patientUserId,
        Long patientId,
        String patientName,
        Instant grantedAt,
        Instant expiresAt
) {
}
