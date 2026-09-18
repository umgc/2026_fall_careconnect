CREATE TABLE IF NOT EXISTS call_telemetry_events (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(120),
    event_type VARCHAR(80) NOT NULL,
    event_source VARCHAR(40) NOT NULL,
    channel VARCHAR(40),
    actor_user_id BIGINT,
    target_user_id BIGINT,
    capture_mode VARCHAR(40),
    status VARCHAR(20),
    sentiment_score DOUBLE PRECISION,
    sentiment_label VARCHAR(40),
    sentiment_notes TEXT,
    analysis_timestamp BIGINT,
    payload_json TEXT,
    metadata_json TEXT,
    error_message TEXT,
    occurred_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_call_telemetry_call_id ON call_telemetry_events(call_id);
CREATE INDEX IF NOT EXISTS idx_call_telemetry_actor ON call_telemetry_events(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_call_telemetry_target ON call_telemetry_events(target_user_id);
CREATE INDEX IF NOT EXISTS idx_call_telemetry_occurred_at ON call_telemetry_events(occurred_at);
