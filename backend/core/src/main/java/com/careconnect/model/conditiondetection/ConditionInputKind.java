package com.careconnect.model.conditiondetection;

/** What a condition model consumes. */
public enum ConditionInputKind {
    /** The patient's own audio track, exported from KVS after the call. */
    PATIENT_AUDIO,
    /** The stored post-call transcript with speaker attribution. */
    TRANSCRIPT
}
