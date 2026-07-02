ALTER TABLE call_recordings
    ADD COLUMN IF NOT EXISTS media_stream_pipeline_id VARCHAR(255) NULL;
