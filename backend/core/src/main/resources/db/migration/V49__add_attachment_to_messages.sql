-- Duplicate of V40 retained for migration ordering on older databases.
-- Attachment metadata stored directly on the message row for fast reads.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS attachment_id BIGINT,
    ADD COLUMN IF NOT EXISTS attachment_name TEXT,
    ADD COLUMN IF NOT EXISTS attachment_content_type TEXT,
    ADD COLUMN IF NOT EXISTS attachment_size BIGINT;

CREATE INDEX IF NOT EXISTS idx_messages_attachment ON messages (attachment_id) WHERE attachment_id IS NOT NULL;
