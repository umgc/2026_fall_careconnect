-- V39__create_messages_table.sql
-- Person-to-person chat messages for in-app messaging feature.
-- Used by MessageController (/v1/api/messages) and ChatMessageWebSocketHandler (/ws/chat).

CREATE TABLE messages (
    id          BIGSERIAL PRIMARY KEY,
    sender_id   BIGINT        NOT NULL,
    receiver_id BIGINT        NOT NULL,
    content     TEXT          NOT NULL,
    timestamp   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_read     BOOLEAN       NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_messages_sender   ON messages (sender_id);
CREATE INDEX idx_messages_receiver ON messages (receiver_id);
CREATE INDEX idx_messages_convo    ON messages (sender_id, receiver_id, timestamp);
