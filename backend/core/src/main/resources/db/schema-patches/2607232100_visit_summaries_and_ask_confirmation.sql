-- Task 1.4 + 6.6 schema patch (ScriptUtils-safe; no dollar-quoted blocks).
CREATE TABLE IF NOT EXISTS visit_summaries
(
    id
    BIGSERIAL
    PRIMARY
    KEY,
    visit_id
    VARCHAR
(
    120
) NOT NULL,
    patient_id BIGINT NULL,
    summary_json TEXT NOT NULL,
    status VARCHAR
(
    24
) NOT NULL,
    transcript_segment_count INTEGER NOT NULL DEFAULT 0,
    generated_by_user_id BIGINT NULL,
    error_message TEXT,
    generated_at TIMESTAMP NOT NULL,
    risk_level VARCHAR
(
    16
),
    caregiver_visibility VARCHAR
(
    16
) NOT NULL DEFAULT 'on_consent',
    summary_confidence DECIMAL
(
    3,
    2
),
    summarization_engine VARCHAR
(
    128
),
    transcript_snapshot_version VARCHAR
(
    80
),
    model_config_version VARCHAR
(
    160
),
    transcript_available BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

CREATE INDEX IF NOT EXISTS idx_visit_summary_visit_id
    ON visit_summaries (visit_id);
CREATE INDEX IF NOT EXISTS idx_visit_summary_generated_at
    ON visit_summaries (generated_at);
CREATE INDEX IF NOT EXISTS idx_visit_summary_patient_id
    ON visit_summaries (patient_id);
CREATE INDEX IF NOT EXISTS idx_visit_summary_caregiver_visibility
    ON visit_summaries (caregiver_visibility);

CREATE TABLE IF NOT EXISTS ai_ask_confirmation_decision
(
    id
    UUID
    PRIMARY
    KEY,
    session_id
    UUID
    NOT
    NULL,
    patient_id
    BIGINT
    NOT
    NULL,
    caller_user_id
    BIGINT
    NOT
    NULL,
    request_id
    UUID
    NULL,
    decision
    VARCHAR
(
    32
) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW
(
)
    );

CREATE INDEX IF NOT EXISTS idx_ai_ask_confirmation_session
    ON ai_ask_confirmation_decision (session_id, patient_id, caller_user_id, created_at DESC);
