package com.careconnect.model.safety;

/** WBS 3.15.6
 *  (sourceFeature) Feature that generated the audit event */
public enum AuditSourceFeature {
    /** Ask AI retrieval and answer generation */
    ASK_AI,
    /** Call and visit summary pipeline */
    SUMMARY,
    /** Confirmation Service (approve-once / approve-for-session / dismiss) */
    CONFIRMATION_SERVICE,
    /** Caregiver visibility grant/revoke/review gate */
    CAREGIVER_VISIBILITY
}
