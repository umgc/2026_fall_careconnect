CREATE TABLE IF NOT EXISTS call_attendees (
    id                 BIGSERIAL PRIMARY KEY,
    call_id            VARCHAR(120) NOT NULL,
    chime_attendee_id  VARCHAR(255) NOT NULL,
    user_id            BIGINT NOT NULL,
    role               VARCHAR(40) NOT NULL,
    joined_at          TIMESTAMP NOT NULL,
    left_at            TIMESTAMP,
    CONSTRAINT uq_call_attendees_call_chime UNIQUE (call_id, chime_attendee_id)
);

CREATE INDEX IF NOT EXISTS idx_call_attendees_call_id ON call_attendees(call_id);
CREATE INDEX IF NOT EXISTS idx_call_attendees_user_id ON call_attendees(user_id);

ALTER TABLE call_recordings
    ADD COLUMN IF NOT EXISTS kvs_pipeline_id VARCHAR(255) NULL;
