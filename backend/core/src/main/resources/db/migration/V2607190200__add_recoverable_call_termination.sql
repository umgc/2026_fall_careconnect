ALTER TABLE call_sessions
    ADD COLUMN IF NOT EXISTS termination_claim_id UUID NULL,
    ADD COLUMN IF NOT EXISTS termination_claimed_by_user_id BIGINT NULL,
    ADD COLUMN IF NOT EXISTS termination_lease_until TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS termination_attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS termination_next_retry_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS termination_last_error TEXT NULL,
    ADD COLUMN IF NOT EXISTS termination_notify_user_ids TEXT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint c
         WHERE c.conrelid = 'call_sessions'::regclass
           AND c.confrelid = 'users'::regclass
           AND c.contype = 'f'
           AND c.conkey = ARRAY[(
               SELECT attnum FROM pg_attribute
                WHERE attrelid = 'call_sessions'::regclass
                  AND attname = 'termination_claimed_by_user_id'
           )]::smallint[]
           AND c.confkey = ARRAY[(
               SELECT attnum FROM pg_attribute
                WHERE attrelid = 'users'::regclass
                  AND attname = 'id'
           )]::smallint[]
    ) THEN
        ALTER TABLE call_sessions
            ADD CONSTRAINT fk_call_sessions_termination_claimed_by
            FOREIGN KEY (termination_claimed_by_user_id) REFERENCES users(id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint c
         WHERE c.conrelid = 'call_sessions'::regclass
           AND c.contype = 'c'
           AND pg_get_constraintdef(c.oid) LIKE '%termination_attempt_count >= 0%'
    ) THEN
        ALTER TABLE call_sessions
            ADD CONSTRAINT ck_call_sessions_termination_attempt_count
            CHECK (termination_attempt_count >= 0);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_call_sessions_termination_retry
    ON call_sessions (termination_next_retry_at, termination_lease_until)
    WHERE status = 'TERMINATING';
