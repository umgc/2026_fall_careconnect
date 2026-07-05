package com.careconnect.model.forms;

/**
 * Stable machine keys for the required hiring and onboarding documents.
 * Each value corresponds to one JSON form definition under
 * {@code src/main/resources/forms/} and to a {@link FormDefinition} row.
 */
public enum FormType {
    /** IRS Form W-4 - Employee's Withholding Certificate. */
    W4,
    /** USCIS Form I-9 - Employment Eligibility Verification. */
    I9,
    /** Direct deposit / payroll banking authorization. */
    DIRECT_DEPOSIT,
    /** Sworn statement / criminal history disclosure. */
    SWORN_DISCLOSURE,
    /** Pre-employment health screening and TB attestation. */
    HEALTH,
    /** General employment application. */
    GENERAL_HIRING,
    /** Conditional-offer pre-hire authorizations and acknowledgements. */
    PRE_HIRE
}
