package com.careconnect.service.ai.indexing;

/** Result of one stale summary citation metadata replay attempt. */
public enum SummaryCitationReplayOutcome {
    UPDATED,
    CURRENT,
    NO_DRAFTS
}
