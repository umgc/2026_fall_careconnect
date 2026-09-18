ALTER TABLE call_recordings
    ADD COLUMN IF NOT EXISTS generation BIGINT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS purpose VARCHAR(32) NOT NULL DEFAULT 'USER_PLAYBACK',
    ADD COLUMN IF NOT EXISTS lifecycle_status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE',
    ADD COLUMN IF NOT EXISTS claim_token UUID,
    ADD COLUMN IF NOT EXISTS claim_lease_until TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS aws_pipeline_id VARCHAR(255),
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_error TEXT,
    ADD COLUMN IF NOT EXISTS owner_user_id BIGINT,
    ADD COLUMN IF NOT EXISTS consented_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS consented_by_user_id BIGINT,
    ADD COLUMN IF NOT EXISTS purge_state VARCHAR(24) NOT NULL DEFAULT 'NONE',
    ADD COLUMN IF NOT EXISTS purge_requested_at TIMESTAMPTZ;

UPDATE call_recordings
SET aws_pipeline_id = pipeline_id
WHERE aws_pipeline_id IS NULL AND pipeline_id IS NOT NULL;

-- Safety precheck for unknown statuses runs in
-- SchemaPatchRunner.verifyRecordingStatePreconditions() (ScriptUtils cannot
-- execute Postgres dollar-quoted DO blocks). Duplicate active ownership is
-- fail-closed by uq_call_recordings_active_generation below.

UPDATE call_recordings
SET owner_user_id = initiated_by_user_id,
    purpose = CASE WHEN initiated_by_user_id IS NULL
                   THEN 'SYSTEM_TRANSCRIPTION' ELSE 'USER_PLAYBACK' END,
    lifecycle_status = CASE status
        WHEN 'STARTED' THEN 'ACTIVE'
        WHEN 'STOP_RETRYABLE' THEN 'STOP_RETRYABLE'
        WHEN 'FINALIZE_RETRYABLE' THEN 'FINALIZE_RETRYABLE'
        WHEN 'STOPPED' THEN 'COMPLETE'
        WHEN 'FAILED' THEN 'FAILED'
    END
WHERE lifecycle_status = 'ACTIVE';

WITH ranked AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY started_at, id) AS generation
    FROM call_recordings
)
UPDATE call_recordings recording
SET generation = ranked.generation
FROM ranked
WHERE recording.id = ranked.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_call_recordings_active_generation
    ON call_recordings (call_id)
    WHERE lifecycle_status IN
        ('RESERVED', 'STARTING', 'ACTIVE', 'STOP_CLAIMED',
         'STOP_RETRYABLE', 'FINALIZE_RETRYABLE', 'PURGE_PENDING');

CREATE UNIQUE INDEX IF NOT EXISTS uq_call_recordings_generation
    ON call_recordings (call_id, generation);

CREATE INDEX IF NOT EXISTS idx_call_recordings_claim
    ON call_recordings (next_retry_at, claim_lease_until, id)
    WHERE lifecycle_status IN
        ('STOP_RETRYABLE', 'FINALIZE_RETRYABLE', 'PURGE_PENDING');

ALTER TABLE call_sessions
    ADD COLUMN IF NOT EXISTS recording_start_elected BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS recording_compensation_outbox (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(120) NOT NULL,
    generation BIGINT NOT NULL,
    resource_type VARCHAR(32) NOT NULL,
    aws_resource_id VARCHAR(255) NOT NULL,
    s3_bucket VARCHAR(255),
    s3_prefix VARCHAR(500),
    state VARCHAR(20) NOT NULL DEFAULT 'READY',
    claim_token UUID,
    claimed_until TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    CONSTRAINT uq_recording_compensation_resource
        UNIQUE (resource_type, aws_resource_id)
);

CREATE INDEX IF NOT EXISTS idx_recording_compensation_claim
    ON recording_compensation_outbox (next_attempt_at, claimed_until, id)
    WHERE completed_at IS NULL;

CREATE TABLE IF NOT EXISTS post_call_transcription_jobs (
    id BIGSERIAL PRIMARY KEY,
    recording_id BIGINT NOT NULL,
    call_id VARCHAR(120) NOT NULL,
    recording_generation BIGINT NOT NULL,
    state VARCHAR(20) NOT NULL DEFAULT 'READY',
    claim_token UUID,
    claimed_until TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    aws_job_name VARCHAR(200) NOT NULL,
    media_bucket VARCHAR(255) NOT NULL,
    media_key VARCHAR(1000) NOT NULL,
    output_bucket VARCHAR(255) NOT NULL,
    output_key VARCHAR(1000) NOT NULL,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    CONSTRAINT uq_post_call_transcription_recording UNIQUE (recording_id),
    CONSTRAINT fk_post_call_transcription_recording
        FOREIGN KEY (recording_id) REFERENCES call_recordings(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_post_call_transcription_claim
    ON post_call_transcription_jobs (next_attempt_at, claimed_until, id)
    WHERE state IN ('READY', 'RETRYABLE', 'CLAIMED', 'RUNNING');
