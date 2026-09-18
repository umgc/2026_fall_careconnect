ALTER TABLE call_transcript_segments
    ADD COLUMN IF NOT EXISTS client_segment_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_call_transcript_client_segment
    ON call_transcript_segments (call_id, client_segment_id)
    WHERE client_segment_id IS NOT NULL;

ALTER TABLE transcript_archive_deletion_outbox
    ADD COLUMN IF NOT EXISTS dead_lettered_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS terminal_error VARCHAR(1000);

DROP INDEX IF EXISTS idx_transcript_archive_deletion_claim;
CREATE INDEX IF NOT EXISTS idx_transcript_archive_deletion_claim
    ON transcript_archive_deletion_outbox (next_attempt_at, claimed_until, id)
    WHERE dead_lettered_at IS NULL;
