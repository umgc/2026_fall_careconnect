package com.careconnect.model.conditiondetection;

import java.util.Set;

/**
 * Lifecycle of a {@link ConditionDetectionRun}. Native claim queries compare these names as
 * strings, so renaming a constant is a schema change.
 */
public enum ConditionRunState {
    READY,
    CLAIMED,
    RUNNING,
    RETRYABLE,
    COMPLETE,
    SKIPPED,
    FAILED;

    /** States the worker may still pick up. */
    public static final Set<ConditionRunState> ACTIVE = Set.of(READY, CLAIMED, RUNNING, RETRYABLE);

    public boolean isTerminal() {
        return this == COMPLETE || this == SKIPPED || this == FAILED;
    }
}
