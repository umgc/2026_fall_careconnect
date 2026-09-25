-- V48__create_messages_table.sql
-- Duplicate of V39 retained for migration ordering on older databases.
-- Idempotent on fresh installs where V39 already created messages.

CREATE TABLE IF NOT EXISTS messages (
    id          BIGSERIAL PRIMARY KEY,
    sender_id   BIGINT        NOT NULL,
    receiver_id BIGINT        NOT NULL,
    content     TEXT          NOT NULL,
    timestamp   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_read     BOOLEAN       NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_messages_sender   ON messages (sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages (receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_convo    ON messages (sender_id, receiver_id, timestamp);
