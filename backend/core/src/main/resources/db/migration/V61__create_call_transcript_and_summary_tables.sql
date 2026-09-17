CREATE TABLE IF NOT EXISTS call_transcript_segments (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(120) NOT NULL,
    speaker_label VARCHAR(60),
    transcript_text TEXT NOT NULL,
    start_ms BIGINT,
    end_ms BIGINT,
    source VARCHAR(80),
    actor_user_id BIGINT,
    occurred_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_call_transcript_call_id
    ON call_transcript_segments (call_id);

CREATE INDEX IF NOT EXISTS idx_call_transcript_actor
    ON call_transcript_segments (actor_user_id);

CREATE INDEX IF NOT EXISTS idx_call_transcript_start_ms
    ON call_transcript_segments (start_ms);

CREATE TABLE IF NOT EXISTS call_summaries (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(120) NOT NULL,
    summary_json TEXT NOT NULL,
    status VARCHAR(24) NOT NULL,
    transcript_segment_count INTEGER NOT NULL DEFAULT 0,
    generated_by_user_id BIGINT,
    error_message TEXT,
    generated_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_call_summary_call_id
    ON call_summaries (call_id);

CREATE INDEX IF NOT EXISTS idx_call_summary_generated_at
    ON call_summaries (generated_at);
