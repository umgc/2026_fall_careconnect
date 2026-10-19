package com.careconnect.repository.projection;

/**
 * Native-query projection for summed sync_completed counters.
 */
public interface SyncCompletedSumProjection {

    Number getAttempted();

    Number getSucceeded();

    Number getFailed();
}
