ALTER TABLE call_sessions
    ADD COLUMN IF NOT EXISTS termination_claim_id UUID NULL,
    ADD COLUMN IF NOT EXISTS termination_claimed_by_user_id BIGINT NULL,
    ADD COLUMN IF NOT EXISTS termination_lease_until TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS termination_attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS termination_next_retry_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS termination_last_error TEXT NULL,
    ADD COLUMN IF NOT EXISTS termination_notify_user_ids TEXT NULL;

-- Plain statements only: SchemaPatchRunner/ScriptUtils splits on ';' and cannot
-- execute Postgres dollar-quoted anonymous blocks.
ALTER TABLE call_sessions DROP CONSTRAINT IF EXISTS fk_call_sessions_termination_claimed_by;
ALTER TABLE call_sessions ADD CONSTRAINT fk_call_sessions_termination_claimed_by
    FOREIGN KEY (termination_claimed_by_user_id) REFERENCES users(id);

ALTER TABLE call_sessions DROP CONSTRAINT IF EXISTS ck_call_sessions_termination_attempt_count;
ALTER TABLE call_sessions ADD CONSTRAINT ck_call_sessions_termination_attempt_count
    CHECK (termination_attempt_count >= 0);

CREATE INDEX IF NOT EXISTS idx_call_sessions_termination_retry
    ON call_sessions (termination_next_retry_at, termination_lease_until)
    WHERE status = 'TERMINATING';
