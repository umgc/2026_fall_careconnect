package com.careconnect.service.ai.indexing;

/**
 * Signals that an indexing outbox row should remain unprocessed without burning
 * attempt budget (e.g. transcript events waiting for patientId).
 */
public class IndexingDeferredException extends RuntimeException {

    public IndexingDeferredException(final String message) {
        super(message);
    }
}
