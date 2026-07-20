-- V2607071921__create_retrieval_index_chunk.sql
--
-- Task 1.5 — Shared Ask AI retrieval index table (TDD §7.1, Hybrid Retrieval Scope).
-- Consumed by IndexWorker (backlog 4.1) after indexing_outbox events are processed.
--
-- Ownership: Platform (Flyway) + Team E (indexer/retrieval consumers).
-- RBAC: every query MUST filter on patient_id (Task 2.3).
--
-- PostgreSQL-specific columns:
--   search_vector  — maintained by trigger from chunk_text (FTS, Task 4.2 precursor)
--   embedding      — vector(1536) for semantic search (Task 4.3)
--
-- Related: V2607071920 (pgvector), V2607032257 (indexing_outbox), RetrievalRecordType enum.

CREATE TABLE IF NOT EXISTS retrieval_index_chunk (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id        BIGINT        NOT NULL,
    record_type       VARCHAR(40)   NOT NULL,
    source_record_id  VARCHAR(120)  NOT NULL,
    chunk_text        TEXT          NOT NULL,
    chunk_metadata    JSONB         NULL,
    search_vector     TSVECTOR      NULL,
    embedding         vector(1536)  NULL,
    indexed_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    consent_scope     VARCHAR(40)   NULL
);

ALTER TABLE retrieval_index_chunk
    ADD CONSTRAINT fk_retrieval_chunk_patient
    FOREIGN KEY (patient_id) REFERENCES patient (id);

-- RBAC scope filter — every retrieval query starts here (FR-AI-1).
CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_patient_id
    ON retrieval_index_chunk (patient_id);

-- Structured prefilter by patient + record type (REQ-SC-7 exclusions at query time).
CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_patient_record_type
    ON retrieval_index_chunk (patient_id, record_type);

-- Idempotent re-indexing and source correlation (summary_id, call_id, etc.).
CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_source
    ON retrieval_index_chunk (source_record_id, record_type);

-- Full-text search over chunk_text (hybrid retrieval keyword leg).
CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_fts
    ON retrieval_index_chunk USING GIN (search_vector);

-- Semantic similarity search (hybrid retrieval vector leg).
-- lists=100 is a starter value; tune after index population (Task 4.4 backfill).
CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_embedding
    ON retrieval_index_chunk USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

COMMENT ON TABLE retrieval_index_chunk IS
    'Ask AI hybrid retrieval index chunks (Task 1.5). Scoped by patient_id; record_type aligns with RetrievalRecordType enum.';

COMMENT ON COLUMN retrieval_index_chunk.patient_id IS
    'Patient entity id (patient.id). Mandatory scope key for every retrieval query (FR-AI-1).';

COMMENT ON COLUMN retrieval_index_chunk.record_type IS
    'Canonical source type (e.g. CALL_SUMMARY, TRANSCRIPT_SEGMENT). Matches RetrievalRecordType.name().';

COMMENT ON COLUMN retrieval_index_chunk.source_record_id IS
    'Stable id of the upstream source row (summary id, call id, document id, etc.) for idempotent indexing.';

COMMENT ON COLUMN retrieval_index_chunk.chunk_text IS
    'Searchable excerpt indexed for FTS and embedding generation. Minimum-necessary text only (FR-AI-9).';

COMMENT ON COLUMN retrieval_index_chunk.chunk_metadata IS
    'Optional JSON metadata: deep links, speaker, timestamps, visibility, content_hash, etc.';

COMMENT ON COLUMN retrieval_index_chunk.search_vector IS
    'PostgreSQL tsvector for full-text search. Auto-maintained from chunk_text via trigger.';

COMMENT ON COLUMN retrieval_index_chunk.embedding IS
    '1536-dim pgvector embedding for semantic search (Bedrock Titan or approved embed model, Task 4.3).';

COMMENT ON COLUMN retrieval_index_chunk.consent_scope IS
    'Caregiver visibility scope at index time: on_consent, auto, or hidden (REQ-SC-8).';

-- Maintain search_vector from chunk_text on write (Task 4.2).
-- Application keyword queries use plainto_tsquery('english', ...) via
-- RetrievalIndexChunkRepository.searchByPatientIdFullText / FullTextSearchService.
-- Follow-up: add Spanish config (to_tsvector('spanish', ...)) for bilingual FTS.
CREATE OR REPLACE FUNCTION retrieval_index_chunk_search_vector_trigger()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', COALESCE(NEW.chunk_text, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_retrieval_index_chunk_search_vector
    BEFORE INSERT OR UPDATE OF chunk_text ON retrieval_index_chunk
    FOR EACH ROW EXECUTE FUNCTION retrieval_index_chunk_search_vector_trigger();
