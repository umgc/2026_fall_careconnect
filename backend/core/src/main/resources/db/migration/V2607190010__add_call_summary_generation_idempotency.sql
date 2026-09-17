ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS transcript_snapshot_version VARCHAR(80),
    ADD COLUMN IF NOT EXISTS model_config_version VARCHAR(160);

CREATE UNIQUE INDEX IF NOT EXISTS uq_call_summary_generation_snapshot
    ON call_summaries (call_id, transcript_snapshot_version, model_config_version)
    WHERE transcript_snapshot_version IS NOT NULL
      AND model_config_version IS NOT NULL;
