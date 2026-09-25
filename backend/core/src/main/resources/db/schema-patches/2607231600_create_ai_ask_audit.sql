-- Catalog mirror of V2607231600 for SchemaPatchLedger (production path).
-- Ask AI FR-AI-10 / REQ-SC-9: immutable completion snapshot + append-only events.

CREATE TABLE IF NOT EXISTS ai_ask_audit_record (
    audit_id UUID PRIMARY KEY,
    request_id UUID NOT NULL UNIQUE,
    session_id UUID,
    client_request_id VARCHAR(64),
    patient_id BIGINT NOT NULL,
    caller_user_id BIGINT NOT NULL,
    caller_role VARCHAR(32) NOT NULL,
    input_modality VARCHAR(8) NOT NULL DEFAULT 'TEXT',
    locale VARCHAR(10) NOT NULL DEFAULT 'en-US',
    query_text_hash VARCHAR(64) NOT NULL,
    query_length INT NOT NULL,
    delivery_status VARCHAR(24) NOT NULL,
    tier SMALLINT NOT NULL DEFAULT 0,
    held BOOLEAN NOT NULL DEFAULT FALSE,
    held_item_id UUID,
    error_code VARCHAR(40),
    answer_text_hash VARCHAR(64),
    answer_length INT,
    citations_json TEXT NOT NULL DEFAULT '[]',
    escalation_json TEXT NOT NULL DEFAULT '{}',
    trigger_codes TEXT NOT NULL DEFAULT '[]',
    validation_findings_json TEXT,
    retrieval_meta_json TEXT NOT NULL DEFAULT '{}',
    scope_json TEXT NOT NULL DEFAULT '{}',
    model_provider VARCHAR(32),
    model_id VARCHAR(128),
    total_latency_ms INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_ask_audit_patient_created
    ON ai_ask_audit_record (patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_ask_audit_caller_created
    ON ai_ask_audit_record (caller_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_ask_audit_session
    ON ai_ask_audit_record (session_id);

CREATE TABLE IF NOT EXISTS ai_ask_audit_event (
    id UUID PRIMARY KEY,
    audit_id UUID NOT NULL,
    event_type VARCHAR(48) NOT NULL,
    event_sequence INT NOT NULL,
    actor_user_id BIGINT,
    payload_json TEXT NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_ai_ask_audit_event_seq UNIQUE (audit_id, event_sequence)
);

CREATE INDEX IF NOT EXISTS idx_ai_ask_audit_event_audit
    ON ai_ask_audit_event (audit_id, event_sequence);

CREATE TABLE IF NOT EXISTS ai_ask_audit_delivery_supplement (
    id UUID PRIMARY KEY,
    audit_id UUID NOT NULL,
    delivery_status VARCHAR(24) NOT NULL,
    final_answer_hash VARCHAR(64),
    citations_json TEXT NOT NULL DEFAULT '[]',
    reviewer_user_id BIGINT,
    reviewed_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_ask_audit_delivery_audit
    ON ai_ask_audit_delivery_supplement (audit_id, created_at DESC);
