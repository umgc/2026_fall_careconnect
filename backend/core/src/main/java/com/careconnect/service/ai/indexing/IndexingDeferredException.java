package com.careconnect.service.ai.indexing;

/**
 * Signals that an indexing outbox row should remain unprocessed.
 *
 * <p>When {@link #burnsAttempt()} is {@code true} (default), {@code IndexWorker}
 * increments {@code attempt_count} so the row eventually dead-letters.
 * When {@code false}, the row is left unprocessed without burning budget
 * (e.g. visit summaries waiting on Task 1.4). {@code IndexWorker} stamps a
 * future {@code claimed_at} (no-burn park hours) so the row is not reclaimed
 * every poll.
 */
public class IndexingDeferredException extends RuntimeException {

    private final boolean burnsAttempt;

    public IndexingDeferredException(final String message) {
        this(message, true);
    }

    public IndexingDeferredException(final String message, final boolean burnsAttempt) {
        super(message);
        this.burnsAttempt = burnsAttempt;
    }

    public boolean burnsAttempt() {
        return burnsAttempt;
    }
}
