package com.careconnect.service.consent;

/**
 * Result of a caregiver-visibility lookup for a specific (caregiver,
 * patient) pair. Combines the relationship {@code status} with the
 * boolean {@code canViewSummaries} decision so the caller can:
 * <ul>
 *   <li>Skip the consent gate entirely when {@code status == NONE}
 *       (user is not registered as a caregiver for this patient at
 *       all — the on_consent policy does not apply to them).</li>
 *   <li>Build a 403 response body distinguishing PENDING_REVIEW from
 *       REVOKED when the gate blocks access.</li>
 * </ul>
 *
 * <p>Mirrors the record contract David is shipping in WBS 3.15.5.
 *
 * @param status              relationship state; see
 *                            {@link CaregiverVisibilityStatus}
 * @param canViewSummaries    {@code true} when the caregiver is
 *                            currently authorized to read summaries
 *                            for this patient
 */
public record CaregiverVisibilityCheck(
        CaregiverVisibilityStatus status,
        boolean canViewSummaries) {

    /**
     * Convenience factory for the "no relationship / gate does not
     * apply" case. Both fields are set to their permissive defaults:
     * {@code status = NONE}, {@code canViewSummaries = true}.
     */
    public static CaregiverVisibilityCheck none() {
        return new CaregiverVisibilityCheck(CaregiverVisibilityStatus.NONE, true);
    }
}
