package com.careconnect.model;

/** Destructive cleanup state for a recording generation. */
public enum RecordingPurgeState {
    NONE,
    REQUESTED,
    STOPPING,
    DELETING,
    COMPLETE
}
