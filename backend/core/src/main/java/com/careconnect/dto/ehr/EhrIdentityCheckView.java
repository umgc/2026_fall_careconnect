package com.careconnect.dto.ehr;

/**
 * A hidden second detail from the incoming record that the patient confirms before choosing a date
 * of birth: name + DOB alone can match two people (M3 feedback). Carried on
 * {@link EhrIdentityConflictView#identityCheck()}.
 *
 * <p>{@code type} is {@code PHONE}, {@code EMAIL} or {@code ZIP}; {@code value} is already the hidden
 * form — the last 4 digits of a phone, an email with its name part masked ({@code j•••@gmail.com}),
 * or the postal code. Masking happens server-side so no raw phone/email ever reaches the wire. The
 * shape matches the frontend {@code IdentityCheck.fromJson} shipped in PR #378, whose own
 * {@code phoneLast4}/{@code maskEmail}/{@code zip5} keep these already-hidden values verbatim.
 */
public record EhrIdentityCheckView(String type, String value) {
}
