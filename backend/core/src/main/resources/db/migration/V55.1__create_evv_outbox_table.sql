-- Create evv_outbox table if it does not already exist.
-- This table was defined in V28 but may not have been applied to older databases
-- that ran migrations before evv_outbox was added to that script.
CREATE TABLE IF NOT EXISTS evv_outbox (
    id             BIGSERIAL PRIMARY KEY,
    evv_record_id  BIGINT NOT NULL REFERENCES evv_record(id),
    destination    VARCHAR(64) NOT NULL,
    payload        JSONB NOT NULL,
    status         VARCHAR(32) NOT NULL DEFAULT 'READY',
    attempts       INT NOT NULL DEFAULT 0,
    last_error     TEXT,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at     TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_outbox_status ON evv_outbox(status);
