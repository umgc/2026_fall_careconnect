ALTER TABLE call_recordings
    ADD COLUMN IF NOT EXISTS concatenation_pipeline_id VARCHAR(255);

ALTER TABLE call_recordings
    ADD COLUMN IF NOT EXISTS concatenation_status VARCHAR(30);

CREATE INDEX IF NOT EXISTS idx_call_recordings_concat_status
    ON call_recordings(concatenation_status);
