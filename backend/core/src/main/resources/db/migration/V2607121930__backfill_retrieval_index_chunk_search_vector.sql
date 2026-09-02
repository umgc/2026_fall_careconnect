-- V2607121930__backfill_retrieval_index_chunk_search_vector.sql
--
-- Task 4.2 — FTS coverage after IndexWorker (Task 4.1) writes.
--
-- The BEFORE INSERT/UPDATE trigger from V2607071921 already maintains
-- search_vector from chunk_text for new writes. This migration:
--   1. Reaffirms the trigger (idempotent REPLACE) so ECS/SchemaPatchRunner
--      and Flyway stay aligned.
--   2. Backfills any rows that may have been inserted while the trigger was
--      missing (NULL search_vector) so keyword retrieval can see them.
--
-- Query path: RetrievalIndexChunkRepository.searchByPatientIdFullText
--             + FullTextSearchService (patient-scoped plainto_tsquery).

CREATE
OR REPLACE FUNCTION retrieval_index_chunk_search_vector_trigger()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector
:= to_tsvector('english', COALESCE(NEW.chunk_text, ''));
RETURN NEW;
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_retrieval_index_chunk_search_vector ON retrieval_index_chunk;
CREATE TRIGGER trg_retrieval_index_chunk_search_vector
    BEFORE INSERT OR
UPDATE OF chunk_text
ON retrieval_index_chunk
    FOR EACH ROW EXECUTE FUNCTION retrieval_index_chunk_search_vector_trigger();

UPDATE retrieval_index_chunk
SET search_vector = to_tsvector('english', COALESCE(chunk_text, ''))
WHERE search_vector IS NULL;
