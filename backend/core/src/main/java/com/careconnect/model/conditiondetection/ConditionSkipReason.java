package com.careconnect.model.conditiondetection;

/** Why a run finished without producing flags. Shown to users in plain words. */
public enum ConditionSkipReason {
    CALL_TOO_SHORT,
    NO_RECORDING,
    NO_PATIENT_AUDIO,
    INSUFFICIENT_SPEECH,
    AUDIO_EXPIRED,
    TRANSCRIPT_UNAVAILABLE,
    TRANSCRIPT_TIMEOUT,
    PATIENT_SPEAKER_UNIDENTIFIED,
    MODEL_UNAVAILABLE
}
