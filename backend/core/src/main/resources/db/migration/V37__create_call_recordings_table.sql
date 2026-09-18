CREATE TABLE IF NOT EXISTS call_recordings (
    id                  BIGSERIAL PRIMARY KEY,
    call_id             VARCHAR(120) NOT NULL,
    pipeline_id         VARCHAR(255),
    s3_bucket           VARCHAR(255),
    s3_prefix           VARCHAR(500),
    status              VARCHAR(20) NOT NULL DEFAULT 'STARTED',
    initiated_by_user_id BIGINT,
    started_at          TIMESTAMP NOT NULL,
    ended_at            TIMESTAMP,
    duration_seconds    BIGINT,
    error_message       TEXT,
    created_at          TIMESTAMP,
    updated_at          TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_call_recordings_call_id ON call_recordings(call_id);
CREATE INDEX IF NOT EXISTS idx_call_recordings_user_id ON call_recordings(initiated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_call_recordings_status ON call_recordings(status);
CREATE INDEX IF NOT EXISTS idx_call_recordings_started_at ON call_recordings(started_at);
