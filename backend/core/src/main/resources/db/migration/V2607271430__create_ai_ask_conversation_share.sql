-- Ask AI conversation share receipts for linked-caregiver medical-record review.
CREATE TABLE IF NOT EXISTS ai_ask_conversation_share (
    id                  UUID PRIMARY KEY,
    patient_id          BIGINT       NOT NULL,
    shared_by_user_id   BIGINT       NOT NULL,
    session_id          UUID,
    recipient_user_ids  TEXT         NOT NULL,
    message_count       INTEGER      NOT NULL,
    transcript_json     TEXT         NOT NULL,
    transcript_sha256   VARCHAR(64)  NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_ask_share_patient
    ON ai_ask_conversation_share (patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_ask_share_shared_by
    ON ai_ask_conversation_share (shared_by_user_id, created_at DESC);

-- Durable soft-dedupe for identical shares from the same caller.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ai_ask_share_dedupe
    ON ai_ask_conversation_share (patient_id, shared_by_user_id, transcript_sha256);
