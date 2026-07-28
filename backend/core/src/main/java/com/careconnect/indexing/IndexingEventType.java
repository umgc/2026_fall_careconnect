package com.careconnect.indexing;

/**
 * Known indexing outbox {@code event_type} values (Task 4.1 / indexing contract).
 */
public final class IndexingEventType {

    public static final String TRANSCRIPT_INDEXED = "TRANSCRIPT_INDEXED";
    public static final String SUMMARY_CREATED = "SUMMARY_CREATED";
    public static final String MAILPIECE_INDEXED = "MAILPIECE_INDEXED";
    public static final String CLINICAL_NOTE_INDEXED = "CLINICAL_NOTE_INDEXED";
    public static final String DOCUMENT_INDEXED = "DOCUMENT_INDEXED";

    private IndexingEventType() {
    }
}
