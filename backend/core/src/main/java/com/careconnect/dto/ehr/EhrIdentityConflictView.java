package com.careconnect.dto.ehr;

/**
 * One identity-conflict row for the patient's DOB confirmation screen
 * (GET /v1/api/ehr/identity-conflicts). Flattened from {@code EhrIdentityConflict}; the field names
 * match the frontend's {@code IdentityConflict.fromJson} (camelCase), and {@code detectedAt} is an
 * ISO-8601 instant string the frontend parses with {@code DateTime.tryParse}.
 *
 * <p>{@code incomingSourceLabel} is the {@code ehr_source.display_name} of the conflict's source;
 * {@code canonicalSourceLabel} is the display name of the source that currently owns the canonical
 * value for this field (from {@code ehr_identity_field_provenance}), or {@code null} when no source
 * has established provenance yet. Both are optional in the frontend model.
 *
 * <p>{@code identityCheck} is an optional hidden second detail (phone/email/ZIP) from the incoming
 * record for the patient to confirm; {@code null} when the source has none. See
 * {@link EhrIdentityCheckView}.
 */
public record EhrIdentityConflictView(
        Long id,
        String fieldName,
        String canonicalValueBefore,
        String incomingValue,
        String canonicalSourceLabel,
        String incomingSourceLabel,
        String status,
        String detectedAt,
        EhrIdentityCheckView identityCheck) {
}
