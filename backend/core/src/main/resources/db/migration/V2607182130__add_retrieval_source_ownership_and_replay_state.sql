-- Forward-only source ownership and citation replay state.
ALTER TABLE retrieval_index_chunk
    ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40) NULL,
    ADD COLUMN IF NOT EXISTS citation_replay_after TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS citation_replay_attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS citation_replay_claimed_until TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_source_identity
    ON retrieval_index_chunk (patient_id, source_kind, source_record_id);

CREATE INDEX IF NOT EXISTS idx_retrieval_summary_replay
    ON retrieval_index_chunk
       (citation_replay_after, patient_id, source_record_id)
    WHERE migration_status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_retrieval_summary_replay_claim
    ON retrieval_index_chunk
       (citation_replay_claimed_until, citation_replay_after,
        patient_id, source_record_id)
    WHERE migration_status = 'ACTIVE';

COMMENT ON COLUMN retrieval_index_chunk.source_kind IS
    'First-class upstream source family used to disambiguate table-local ids.';
COMMENT ON COLUMN retrieval_index_chunk.citation_replay_after IS
    'Typed retry eligibility timestamp for citation metadata replay.';
COMMENT ON COLUMN retrieval_index_chunk.citation_replay_attempts IS
    'Number of failed citation metadata replay attempts.';
COMMENT ON COLUMN retrieval_index_chunk.citation_replay_claimed_until IS
    'Lease expiry for multi-instance citation metadata replay claims.';
COMMENT ON COLUMN retrieval_index_chunk.migration_status IS
    'Retrieval eligibility during source identity migration: ACTIVE or QUARANTINED.';
