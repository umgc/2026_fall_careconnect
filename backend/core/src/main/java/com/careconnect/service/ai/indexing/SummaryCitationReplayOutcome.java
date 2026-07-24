package com.careconnect.service.ai.indexing;

/**
 * Result of one stale summary citation metadata replay attempt.
 *
 * <p>{@link #isTerminal()} outcomes must quarantine or stop polling the source.
 * {@link #isRetryable()} outcomes may be claimed again after backoff.
 */
public enum SummaryCitationReplayOutcome {
    UPDATED,
    CURRENT,
    BUSY,
    RETRYABLE,
    TERMINAL_QUARANTINED;

    public boolean isTerminal() {
        return this == TERMINAL_QUARANTINED;
    }

    public boolean isRetryable() {
        return this == BUSY || this == RETRYABLE;
    }
}
