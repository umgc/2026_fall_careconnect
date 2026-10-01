package com.careconnect.model;

/**
 * Durable recording lifecycle, including ownership-preserving retry states.
 */
public enum RecordingLifecycleStatus {
    RESERVED,
    STARTING,
    ACTIVE,
    STOP_CLAIMED,
    STOP_RETRYABLE,
    FINALIZE_RETRYABLE,
    PURGE_PENDING,
    COMPLETE,
    FAILED
}
