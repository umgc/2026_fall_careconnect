-- Forward additive repair for databases where Hibernate created tables before
-- migrations, and for databases that already applied V2607182130.
ALTER TABLE retrieval_index_chunk
    ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS patient_id BIGINT,
    ADD COLUMN IF NOT EXISTS record_type VARCHAR(40),
    ADD COLUMN IF NOT EXISTS source_record_id VARCHAR(120),
    ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40),
    ADD COLUMN IF NOT EXISTS chunk_text TEXT,
    ADD COLUMN IF NOT EXISTS chunk_metadata JSONB,
    ADD COLUMN IF NOT EXISTS search_vector TSVECTOR,
    ADD COLUMN IF NOT EXISTS embedding vector(1536),
    ADD COLUMN IF NOT EXISTS indexed_at TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN IF NOT EXISTS consent_scope VARCHAR(40),
    ADD COLUMN IF NOT EXISTS citation_replay_after TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS citation_replay_attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS citation_replay_claimed_until TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS citation_replay_claim_token UUID,
    ADD COLUMN IF NOT EXISTS migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE';

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_retrieval_chunk_patient' AND contype = 'f') THEN
        ALTER TABLE retrieval_index_chunk
            ADD CONSTRAINT fk_retrieval_chunk_patient
            FOREIGN KEY (patient_id) REFERENCES patient(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_call_sessions_patient' AND contype = 'f') THEN
        ALTER TABLE call_sessions ADD CONSTRAINT fk_call_sessions_patient
            FOREIGN KEY (patient_id) REFERENCES patient(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_call_sessions_created_by' AND contype = 'f') THEN
        ALTER TABLE call_sessions ADD CONSTRAINT fk_call_sessions_created_by
            FOREIGN KEY (created_by_user_id) REFERENCES users(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_call_participants_session' AND contype = 'f') THEN
        ALTER TABLE call_participants ADD CONSTRAINT fk_call_participants_session
            FOREIGN KEY (call_session_id) REFERENCES call_sessions(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_call_participants_user' AND contype = 'f') THEN
        ALTER TABLE call_participants ADD CONSTRAINT fk_call_participants_user
            FOREIGN KEY (user_id) REFERENCES users(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_call_participants_invited_by' AND contype = 'f') THEN
        ALTER TABLE call_participants ADD CONSTRAINT fk_call_participants_invited_by
            FOREIGN KEY (invited_by_user_id) REFERENCES users(id);
    END IF;
END $$;

-- Untyped legacy summary rows are not retrieval-eligible until an authoritative
-- patient/source reconciliation promotes them and assigns source_kind.
UPDATE retrieval_index_chunk
SET migration_status = 'QUARANTINED',
    citation_replay_claimed_until = NULL,
    citation_replay_claim_token = NULL
WHERE source_kind IS NULL
  AND record_type IN (
    'CALL_SUMMARY', 'VISIT_SUMMARY', 'SUMMARY_ACTION_ITEM',
    'SUMMARY_APPOINTMENT', 'SUMMARY_CARE_INSTRUCTION',
    'SUMMARY_CONDITION', 'SUMMARY_SOAP', 'SUMMARY_CLINICAL_OBSERVATION')
  AND migration_status = 'ACTIVE';

COMMENT ON COLUMN retrieval_index_chunk.citation_replay_claim_token IS
    'UUID fencing token required to release, fail, or quarantine a replay lease.';
