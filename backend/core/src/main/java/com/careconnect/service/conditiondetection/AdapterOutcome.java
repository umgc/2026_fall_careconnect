package com.careconnect.service.conditiondetection;

import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import java.util.List;

/** Result of one {@link ConditionModelAdapter#analyze} call. */
public sealed interface AdapterOutcome
        permits AdapterOutcome.Completed, AdapterOutcome.Skipped, AdapterOutcome.Deferred {

    /** The model ran; one finding per reported condition. */
    record Completed(List<ConditionFinding> findings, Double speechSeconds)
            implements AdapterOutcome {
        public Completed {
            findings = List.copyOf(findings);
        }
    }

    /** Permanently no result for this call. */
    record Skipped(ConditionSkipReason reason, Double speechSeconds) implements AdapterOutcome {
        public Skipped(final ConditionSkipReason reason) {
            this(reason, null);
        }
    }

    /** Input not ready yet; re-queue without consuming an attempt. */
    record Deferred(long delaySeconds) implements AdapterOutcome {
    }
}
