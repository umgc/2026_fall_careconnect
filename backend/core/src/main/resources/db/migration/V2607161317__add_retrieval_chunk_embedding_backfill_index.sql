-- V2607161317__add_retrieval_chunk_embedding_backfill_index.sql
--
-- Task 4.4 — optional partial index for embedding backfill scans (NULL + embeddable chunk_text).
-- Canonical reference SQL; production applies via SchemaPatchRunner (not Flyway at ECS deploy).
-- Speeds findMissingEmbeddingsForBackfill ORDER BY indexed_at during large backfills.

CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_embedding_null_backfill
    ON retrieval_index_chunk (indexed_at ASC NULLS LAST, id ASC)
    WHERE embedding IS NULL
      AND chunk_text IS NOT NULL
      AND TRIM(BOTH FROM chunk_text) <> '';

COMMENT ON INDEX idx_retrieval_chunk_embedding_null_backfill IS
    'Optional DBA follow-up for Task 4.4 embedding backfill worker (oldest NULL embeddings first).';
