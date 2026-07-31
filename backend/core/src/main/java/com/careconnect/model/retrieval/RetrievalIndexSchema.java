package com.careconnect.model.retrieval;

/**
 * Schema constants for the Ask AI {@code retrieval_index_chunk} table (Tasks 1.5 / 1.6).
 */
public final class RetrievalIndexSchema {

    public static final String TABLE_NAME = "retrieval_index_chunk";

    /**
     * Embedding dimension for pgvector column. Locked to Bedrock
     * {@code amazon.titan-embed-text-v1} (1536-d). Titan Embed Text v2 tops out at
     * 1024-d and requires a column migration before it can be used.
     */
    public static final int EMBEDDING_DIMENSION = 1536;

    /**
     * PostgreSQL text-search configuration used by the {@code search_vector} trigger
     * and {@code plainto_tsquery} keyword leg (Task 4.2). Spanish bilingual FTS remains a
     * later follow-up (needs {@code search_vector_es} / dual {@code to_tsvector} migration).
     */
    public static final String FTS_TEXT_SEARCH_CONFIG = "english";

    /** Soft cap on user query length passed to {@code plainto_tsquery}. */
    public static final int FTS_QUERY_MAX_LENGTH = 500;

    public static final int RECORD_TYPE_MAX_LENGTH = 40;
    public static final int SOURCE_RECORD_ID_MAX_LENGTH = 120;
    public static final int CONSENT_SCOPE_MAX_LENGTH = 40;

    private RetrievalIndexSchema() {
    }
}
