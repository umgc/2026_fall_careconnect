-- Ask AI share recipient rows (queryable ACL) + durable OCR outbox.
CREATE TABLE IF NOT EXISTS ai_ask_share_recipient
(
    share_id
    UUID
    NOT
    NULL,
    user_id
    BIGINT
    NOT
    NULL,
    PRIMARY
    KEY
(
    share_id,
    user_id
),
    CONSTRAINT fk_ai_ask_share_recipient_share
    FOREIGN KEY
(
    share_id
) REFERENCES ai_ask_conversation_share
(
    id
) ON DELETE CASCADE
    );

CREATE INDEX IF NOT EXISTS idx_ai_ask_share_recipient_user
    ON ai_ask_share_recipient (user_id, share_id);

CREATE TABLE IF NOT EXISTS ask_ai_ocr_outbox
(
    id
    BIGSERIAL
    PRIMARY
    KEY,
    file_id
    BIGINT
    NOT
    NULL,
    status
    VARCHAR
(
    32
) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP
                         WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_ask_ai_ocr_outbox_file UNIQUE
(
    file_id
)
    );

CREATE INDEX IF NOT EXISTS idx_ask_ai_ocr_outbox_pending
    ON ask_ai_ocr_outbox (status, updated_at)
    WHERE status IN ('PENDING', 'FAILED');
