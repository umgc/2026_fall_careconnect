-- Tier-2 HITL hold queue for Ask AI (REQ-SC-4).
-- TEXT columns store JSON payloads for H2/Postgres portability.

CREATE TABLE IF NOT EXISTS ai_held_item (
    id UUID PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    requester_user_id BIGINT NOT NULL,
    session_id UUID,
    audit_id UUID NOT NULL,
    request_id UUID,
    source_surface VARCHAR(32) NOT NULL,
    status VARCHAR(24) NOT NULL,
    tier SMALLINT NOT NULL DEFAULT 2,
    trigger_codes TEXT NOT NULL,
    query_text_hash VARCHAR(64),
    draft_answer TEXT NOT NULL,
    final_answer TEXT,
    citations_json TEXT NOT NULL,
    validation_findings_json TEXT,
    reviewer_user_id BIGINT,
    reviewed_at TIMESTAMPTZ,
    review_notes VARCHAR(500),
    delivery_status VARCHAR(32) NOT NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_held_patient_status
    ON ai_held_item (patient_id, status);

CREATE INDEX IF NOT EXISTS idx_held_pending
    ON ai_held_item (status)
    WHERE status = 'PENDING_REVIEW';

CREATE INDEX IF NOT EXISTS idx_held_requester
    ON ai_held_item (requester_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ai_safety_audit_event (
    id UUID PRIMARY KEY,
    audit_id UUID NOT NULL,
    held_item_id UUID,
    event_type VARCHAR(40) NOT NULL,
    actor_user_id BIGINT,
    payload_json TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_safety_audit_audit_id
    ON ai_safety_audit_event (audit_id, created_at);

CREATE INDEX IF NOT EXISTS idx_ai_safety_audit_held_item
    ON ai_safety_audit_event (held_item_id, created_at);
