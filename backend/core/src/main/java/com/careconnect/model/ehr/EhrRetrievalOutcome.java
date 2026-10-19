package com.careconnect.model.ehr;

/**
 * Outcome of a single EHR retrieval attempt, as required by the MedicareApiClient build
 * ticket: one audit event per attempt covering success, retry, failure and empty.
 */
public enum EhrRetrievalOutcome {

    /** The source returned at least one record. */
    SUCCESS,

    /** The source answered successfully but returned no records. */
    EMPTY,

    /** The attempt failed and will be retried; a terminal attempt records FAILURE instead. */
    RETRY,

    /** The attempt failed and was not retried further. */
    FAILURE
}
