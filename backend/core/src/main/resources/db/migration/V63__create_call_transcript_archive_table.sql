CREATE TABLE IF NOT EXISTS call_transcript_archives (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(120) NOT NULL,
    storage_provider VARCHAR(24) NOT NULL,
    storage_key VARCHAR(512) NOT NULL,
    segment_count INTEGER NOT NULL DEFAULT 0,
    transcript_chars INTEGER NOT NULL DEFAULT 0,
    participant_user_ids VARCHAR(512),
    sha256_checksum VARCHAR(128),
    archived_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_call_transcript_archive_call_id
    ON call_transcript_archives (call_id);

CREATE INDEX IF NOT EXISTS idx_call_transcript_archive_archived_at
    ON call_transcript_archives (archived_at);
