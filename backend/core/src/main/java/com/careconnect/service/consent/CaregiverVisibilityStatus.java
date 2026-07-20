package com.careconnect.service.consent;

/**
 * Registered relationship state of a caregiver toward a specific patient
 * for the purposes of consent-gated summary access (TC-E-SUM-009).
 *
 * <p>Mirrors the enum contract David is shipping in WBS 3.15.5. Values
 * kept in sync with the real {@code CaregiverVisibilityService}
 * implementation so the stub swap is a one-line constructor-injection
 * change when his PR lands.
 */
public enum CaregiverVisibilityStatus {

    /**
     * No registered caregiver relationship for this (caregiver, patient)
     * pair. The consent gate does NOT apply to this user for this
     * patient; they either pass or fail via the surrounding four-way
     * access check on their own merits.
     */
    NONE,

    /**
     * Caregiver has requested visibility for this patient but has not
     * yet been approved. {@code canViewSummaries} is expected to be
     * {@code false} while in this state.
     */
    PENDING_REVIEW,

    /**
     * Caregiver had approved visibility that was subsequently revoked.
     * {@code canViewSummaries} is expected to be {@code false} while
     * in this state.
     */
    REVOKED
}
