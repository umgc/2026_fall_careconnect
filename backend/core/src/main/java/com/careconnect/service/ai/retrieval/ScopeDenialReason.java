package com.careconnect.service.ai.retrieval;

/**
 * Machine-readable reason for an Ask AI scope denial (Task 2.6 / SCOPE_DENIED audit event).
 */
public enum ScopeDenialReason {
    PATIENT_OUT_OF_SCOPE,
    PATIENT_NOT_FOUND,
    NO_PERMITTED_SOURCE_TYPES,
    UNSUPPORTED_ROLE
}
