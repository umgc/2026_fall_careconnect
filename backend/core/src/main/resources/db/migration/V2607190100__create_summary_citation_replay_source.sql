-- Source-level ownership for citation replay.  Chunk-level replay columns remain
-- temporarily for backwards-compatible reads, but are no longer claim authority.
ALTER TABLE retrieval_index_chunk
    ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40),
    ADD COLUMN IF NOT EXISTS citation_replay_after TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS citation_replay_attempts INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS citation_replay_claimed_until TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS citation_replay_claim_token UUID,
    ADD COLUMN IF NOT EXISTS migration_status VARCHAR(24) DEFAULT 'ACTIVE';

UPDATE retrieval_index_chunk SET id = gen_random_uuid() WHERE id IS NULL;
UPDATE retrieval_index_chunk SET indexed_at = now() WHERE indexed_at IS NULL;
UPDATE retrieval_index_chunk SET citation_replay_attempts = 0
WHERE citation_replay_attempts IS NULL;
UPDATE retrieval_index_chunk SET migration_status = 'ACTIVE'
WHERE migration_status IS NULL;
UPDATE retrieval_index_chunk
SET citation_replay_claimed_until = NULL,
    citation_replay_claim_token = NULL
WHERE (citation_replay_claimed_until IS NULL)
   <> (citation_replay_claim_token IS NULL);

ALTER TABLE retrieval_index_chunk
    ALTER COLUMN id SET DEFAULT gen_random_uuid(),
    ALTER COLUMN indexed_at SET DEFAULT now(),
    ALTER COLUMN citation_replay_attempts SET DEFAULT 0,
    ALTER COLUMN migration_status SET DEFAULT 'ACTIVE';

-- Validated checks let PostgreSQL prove NOT NULL without a second table scan,
-- reducing the ACCESS EXCLUSIVE lock window for an in-place production upgrade.
ALTER TABLE retrieval_index_chunk
    DROP CONSTRAINT IF EXISTS ck_retrieval_id_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_patient_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_record_type_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_source_record_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_chunk_text_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_indexed_at_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_attempts_nn,
    DROP CONSTRAINT IF EXISTS ck_retrieval_status_nn;

ALTER TABLE retrieval_index_chunk
    ADD CONSTRAINT ck_retrieval_id_nn CHECK (id IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_patient_nn CHECK (patient_id IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_record_type_nn CHECK (record_type IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_source_record_nn CHECK (source_record_id IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_chunk_text_nn CHECK (chunk_text IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_indexed_at_nn CHECK (indexed_at IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_attempts_nn CHECK (citation_replay_attempts IS NOT NULL) NOT VALID,
    ADD CONSTRAINT ck_retrieval_status_nn CHECK (migration_status IS NOT NULL) NOT VALID;

ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_id_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_patient_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_record_type_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_source_record_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_chunk_text_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_indexed_at_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_attempts_nn;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_status_nn;

ALTER TABLE retrieval_index_chunk
    ALTER COLUMN id SET NOT NULL,
    ALTER COLUMN patient_id SET NOT NULL,
    ALTER COLUMN record_type SET NOT NULL,
    ALTER COLUMN source_record_id SET NOT NULL,
    ALTER COLUMN chunk_text SET NOT NULL,
    ALTER COLUMN indexed_at SET NOT NULL,
    ALTER COLUMN citation_replay_attempts SET NOT NULL,
    ALTER COLUMN migration_status SET NOT NULL;

ALTER TABLE retrieval_index_chunk
    DROP CONSTRAINT ck_retrieval_id_nn,
    DROP CONSTRAINT ck_retrieval_patient_nn,
    DROP CONSTRAINT ck_retrieval_record_type_nn,
    DROP CONSTRAINT ck_retrieval_source_record_nn,
    DROP CONSTRAINT ck_retrieval_chunk_text_nn,
    DROP CONSTRAINT ck_retrieval_indexed_at_nn,
    DROP CONSTRAINT ck_retrieval_attempts_nn,
    DROP CONSTRAINT ck_retrieval_status_nn;

-- Plain statements only: SchemaPatchLedger/ScriptUtils splits on ';' and cannot
-- execute Postgres dollar-quoted anonymous blocks.
ALTER TABLE retrieval_index_chunk
    DROP CONSTRAINT IF EXISTS retrieval_index_chunk_pkey;
ALTER TABLE retrieval_index_chunk
    ADD CONSTRAINT retrieval_index_chunk_pkey PRIMARY KEY (id);

CREATE TABLE IF NOT EXISTS summary_citation_replay_source (
    patient_id       BIGINT       NOT NULL,
    source_kind      VARCHAR(40)  NOT NULL,
    source_record_id VARCHAR(120) NOT NULL,
    replay_after     TIMESTAMPTZ  NULL,
    attempts         INTEGER      NOT NULL DEFAULT 0,
    claimed_until    TIMESTAMPTZ  NULL,
    claim_token      UUID         NULL,
    migration_status VARCHAR(24)  NOT NULL DEFAULT 'ACTIVE',
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_summary_citation_replay_source
        PRIMARY KEY (patient_id, source_kind, source_record_id),
    CONSTRAINT ck_summary_replay_status
        CHECK (migration_status IN ('ACTIVE', 'QUARANTINED')),
    CONSTRAINT ck_summary_replay_attempts
        CHECK (attempts >= 0),
    CONSTRAINT ck_summary_replay_source_kind
        CHECK (source_kind IN ('CALL_SUMMARY', 'VISIT_SUMMARY')),
    CONSTRAINT ck_summary_replay_lease_token
        CHECK ((claimed_until IS NULL) = (claim_token IS NULL))
);

ALTER TABLE summary_citation_replay_source
    ADD COLUMN IF NOT EXISTS patient_id BIGINT,
    ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40),
    ADD COLUMN IF NOT EXISTS source_record_id VARCHAR(120),
    ADD COLUMN IF NOT EXISTS replay_after TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS attempts INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS claimed_until TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS claim_token UUID,
    ADD COLUMN IF NOT EXISTS migration_status VARCHAR(24) DEFAULT 'ACTIVE',
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE summary_citation_replay_source SET attempts = 0 WHERE attempts IS NULL;
UPDATE summary_citation_replay_source SET migration_status = 'ACTIVE'
WHERE migration_status IS NULL;
UPDATE summary_citation_replay_source SET created_at = now() WHERE created_at IS NULL;
UPDATE summary_citation_replay_source SET updated_at = now() WHERE updated_at IS NULL;
UPDATE summary_citation_replay_source
SET claimed_until = NULL, claim_token = NULL
WHERE (claimed_until IS NULL) <> (claim_token IS NULL);

ALTER TABLE summary_citation_replay_source
    ALTER COLUMN attempts SET DEFAULT 0,
    ALTER COLUMN migration_status SET DEFAULT 'ACTIVE',
    ALTER COLUMN created_at SET DEFAULT now(),
    ALTER COLUMN updated_at SET DEFAULT now(),
    ALTER COLUMN patient_id SET NOT NULL,
    ALTER COLUMN source_kind SET NOT NULL,
    ALTER COLUMN source_record_id SET NOT NULL,
    ALTER COLUMN attempts SET NOT NULL,
    ALTER COLUMN migration_status SET NOT NULL,
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE summary_citation_replay_source
    DROP CONSTRAINT IF EXISTS ck_summary_replay_status,
    DROP CONSTRAINT IF EXISTS ck_summary_replay_attempts,
    DROP CONSTRAINT IF EXISTS ck_summary_replay_source_kind,
    DROP CONSTRAINT IF EXISTS ck_summary_replay_lease_token;

ALTER TABLE summary_citation_replay_source
    ADD CONSTRAINT ck_summary_replay_status
        CHECK (migration_status IN ('ACTIVE', 'QUARANTINED')) NOT VALID,
    ADD CONSTRAINT ck_summary_replay_attempts
        CHECK (attempts >= 0) NOT VALID,
    ADD CONSTRAINT ck_summary_replay_source_kind
        CHECK (source_kind IN ('CALL_SUMMARY', 'VISIT_SUMMARY')) NOT VALID,
    ADD CONSTRAINT ck_summary_replay_lease_token
        CHECK ((claimed_until IS NULL) = (claim_token IS NULL)) NOT VALID;

ALTER TABLE summary_citation_replay_source VALIDATE CONSTRAINT ck_summary_replay_status;
ALTER TABLE summary_citation_replay_source VALIDATE CONSTRAINT ck_summary_replay_attempts;
ALTER TABLE summary_citation_replay_source VALIDATE CONSTRAINT ck_summary_replay_source_kind;
ALTER TABLE summary_citation_replay_source VALIDATE CONSTRAINT ck_summary_replay_lease_token;

ALTER TABLE summary_citation_replay_source
    DROP CONSTRAINT IF EXISTS pk_summary_citation_replay_source;
ALTER TABLE summary_citation_replay_source
    ADD CONSTRAINT pk_summary_citation_replay_source
    PRIMARY KEY (patient_id, source_kind, source_record_id);

ALTER TABLE summary_citation_replay_source
    DROP CONSTRAINT IF EXISTS fk_summary_replay_patient;
ALTER TABLE summary_citation_replay_source
    ADD CONSTRAINT fk_summary_replay_patient
    FOREIGN KEY (patient_id) REFERENCES patient(id) NOT VALID;
ALTER TABLE summary_citation_replay_source
    VALIDATE CONSTRAINT fk_summary_replay_patient;

CREATE INDEX IF NOT EXISTS idx_summary_replay_claim_fair
    ON summary_citation_replay_source
       (replay_after ASC NULLS FIRST, attempts ASC, patient_id, source_kind, source_record_id)
    WHERE migration_status = 'ACTIVE' AND claim_token IS NULL;

CREATE INDEX IF NOT EXISTS idx_summary_replay_expired_claim
    ON summary_citation_replay_source
       (claimed_until ASC, replay_after ASC NULLS FIRST, patient_id, source_kind, source_record_id)
    WHERE migration_status = 'ACTIVE' AND claim_token IS NOT NULL;

-- Fail closed before resolving any legacy ownership.
UPDATE retrieval_index_chunk
SET migration_status = 'QUARANTINED',
    citation_replay_claimed_until = NULL,
    citation_replay_claim_token = NULL
WHERE source_kind IS NULL
  AND migration_status = 'ACTIVE'
  AND record_type IN (
    'CALL_SUMMARY', 'VISIT_SUMMARY', 'SUMMARY_ACTION_ITEM',
    'SUMMARY_APPOINTMENT', 'SUMMARY_CARE_INSTRUCTION',
    'SUMMARY_CONDITION', 'SUMMARY_SOAP', 'SUMMARY_CLINICAL_OBSERVATION');

-- Typed canonical call sources are safe to register directly.
INSERT INTO summary_citation_replay_source (
    patient_id, source_kind, source_record_id)
SELECT DISTINCT ric.patient_id, 'CALL_SUMMARY', ric.source_record_id
FROM retrieval_index_chunk ric
WHERE ric.migration_status = 'ACTIVE'
  AND ric.source_kind = 'CALL_SUMMARY'
  AND ric.source_record_id ~ '^call-summary:[0-9]+$'
ON CONFLICT (patient_id, source_kind, source_record_id) DO NOTHING;

-- Recovery for quarantined numeric rows is deliberately copy/replay, never an
-- in-place promotion.  A matching authoritative call_summaries row establishes
-- call ownership and patient scope; the numeric rows stay quarantined because a
-- visit summary with the same table-local id may also have produced them.
INSERT INTO summary_citation_replay_source (
    patient_id, source_kind, source_record_id)
SELECT DISTINCT ric.patient_id, 'CALL_SUMMARY', 'call-summary:' || cs.id
FROM retrieval_index_chunk ric
JOIN call_summaries cs
  ON cs.id::text = ric.source_record_id
 AND cs.patient_id = ric.patient_id
WHERE ric.migration_status = 'QUARANTINED'
  AND ric.source_kind IS NULL
  AND ric.source_record_id ~ '^[0-9]+$'
  AND ric.record_type IN (
    'CALL_SUMMARY', 'VISIT_SUMMARY', 'SUMMARY_ACTION_ITEM',
    'SUMMARY_APPOINTMENT', 'SUMMARY_CARE_INSTRUCTION',
    'SUMMARY_CONDITION', 'SUMMARY_SOAP', 'SUMMARY_CLINICAL_OBSERVATION')
ON CONFLICT (patient_id, source_kind, source_record_id) DO NOTHING;

-- Row-level invariants remain enforced while the compatibility columns exist.
ALTER TABLE retrieval_index_chunk
    DROP CONSTRAINT IF EXISTS ck_retrieval_migration_status,
    DROP CONSTRAINT IF EXISTS ck_retrieval_replay_attempts,
    DROP CONSTRAINT IF EXISTS ck_retrieval_source_kind,
    DROP CONSTRAINT IF EXISTS ck_retrieval_replay_lease_token;

ALTER TABLE retrieval_index_chunk
    ADD CONSTRAINT ck_retrieval_migration_status
        CHECK (migration_status IN ('ACTIVE', 'QUARANTINED')) NOT VALID,
    ADD CONSTRAINT ck_retrieval_replay_attempts
        CHECK (citation_replay_attempts >= 0) NOT VALID,
    ADD CONSTRAINT ck_retrieval_source_kind
        CHECK (source_kind IS NULL OR source_kind IN (
            'CALL_SUMMARY', 'VISIT_SUMMARY')) NOT VALID,
    ADD CONSTRAINT ck_retrieval_replay_lease_token
        CHECK ((citation_replay_claimed_until IS NULL) =
               (citation_replay_claim_token IS NULL)) NOT VALID;

ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_migration_status;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_replay_attempts;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_source_kind;
ALTER TABLE retrieval_index_chunk VALIDATE CONSTRAINT ck_retrieval_replay_lease_token;
