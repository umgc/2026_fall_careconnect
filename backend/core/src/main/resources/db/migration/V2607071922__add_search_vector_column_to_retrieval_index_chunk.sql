-- Ensure search_vector column exists on retrieval_index_chunk
-- Required by the FTS trigger created in V2607071921d
ALTER TABLE retrieval_index_chunk
    ADD COLUMN IF NOT EXISTS search_vector tsvector;