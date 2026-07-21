CREATE TABLE IF NOT EXISTS call_transcript_archive_lifecycle (
    call_id VARCHAR(120) PRIMARY KEY,
    generation BIGINT NOT NULL DEFAULT 0,
    purged BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_transcript_archive_generation CHECK (generation >= 0)
);

CREATE TABLE IF NOT EXISTS transcript_archive_deletion_outbox (
    id BIGSERIAL PRIMARY KEY,
    storage_key VARCHAR(512) NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_until TIMESTAMPTZ,
    claim_token UUID,
    last_error VARCHAR(1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_transcript_archive_deletion_key UNIQUE (storage_key),
    CONSTRAINT ck_transcript_archive_deletion_attempts CHECK (attempts >= 0),
    CONSTRAINT ck_transcript_archive_deletion_lease
        CHECK ((claimed_until IS NULL) = (claim_token IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_transcript_archive_deletion_claim
    ON transcript_archive_deletion_outbox
       (next_attempt_at, claimed_until, id);
