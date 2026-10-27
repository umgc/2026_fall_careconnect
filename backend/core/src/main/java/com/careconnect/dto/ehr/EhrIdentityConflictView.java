package com.careconnect.dto.ehr;

/**
 * One identity-conflict row for the patient's DOB confirmation screen
 * (GET /v1/api/ehr/identity-conflicts). Flattened from {@code EhrIdentityConflict}; the field names
 * match the frontend's {@code IdentityConflict.fromJson} (camelCase), and {@code detectedAt} is an
 * ISO-8601 instant string the frontend parses with {@code DateTime.tryParse}.
 *
 * <p>{@code canonicalSourceLabel} / {@code incomingSourceLabel} are optional in that model and are
 * intentionally omitted here: the store keys conflicts by {@code source_id}, not a display label, and
 * deriving labels is out of scope for the I3e interim.
 */
public record EhrIdentityConflictView(
        Long id,
        String fieldName,
        String canonicalValueBefore,
        String incomingValue,
        String status,
        String detectedAt) {
}
