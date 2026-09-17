-- Attachment metadata stored directly on the message row for fast reads.
-- attachment_id references user_files(id) (nullable — text messages have no attachment).
ALTER TABLE messages
    ADD COLUMN attachment_id           BIGINT,
    ADD COLUMN attachment_name         TEXT,
    ADD COLUMN attachment_content_type TEXT,
    ADD COLUMN attachment_size         BIGINT;

CREATE INDEX idx_messages_attachment ON messages (attachment_id) WHERE attachment_id IS NOT NULL;
