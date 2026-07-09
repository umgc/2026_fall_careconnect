package com.careconnect.repository.projection;

/** Native-query projection for summed sync_completed counters. */
public interface SyncCompletedSumProjection {

  long getAttempted();

  long getSucceeded();

  long getFailed();
}
