package com.careconnect.model.visibility;

/**
 * WBS 3.15.5: enum for a caregiver's access to a patient's summaries
 */
public enum VisibilityStatus {
    /**
     * Requested and waiting for the pre-share review gate. Not  viewable
     */
    PENDING_REVIEW,
    /**
     * Reviewer approved, caregiver can view summaries
     */
    GRANTED,
    /**
     * Denied permissions
     */
    REVOKED
}
