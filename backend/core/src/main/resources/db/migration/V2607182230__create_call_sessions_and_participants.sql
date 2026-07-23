-- Reference migration for durable call authorization.
-- Production currently applies the mirrored idempotent DDL through SchemaPatchRunner.

CREATE TABLE IF NOT EXISTS call_sessions (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(120) NOT NULL,
    patient_id BIGINT NOT NULL REFERENCES patient(id),
    created_by_user_id BIGINT NOT NULL REFERENCES users(id),
    scheduled_visit_id BIGINT NULL,
    chime_meeting_id VARCHAR(255) NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'CREATED',
    ended_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT uq_call_sessions_call_id UNIQUE (call_id)
);

CREATE TABLE IF NOT EXISTS call_participants (
    id BIGSERIAL PRIMARY KEY,
    call_session_id BIGINT NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id),
    invited_by_user_id BIGINT NULL REFERENCES users(id),
    status VARCHAR(24) NOT NULL DEFAULT 'INVITED',
    joined_at TIMESTAMP NULL,
    left_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT uq_call_participants_session_user UNIQUE (call_session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_call_sessions_patient_id
    ON call_sessions(patient_id);
CREATE INDEX IF NOT EXISTS idx_call_sessions_creator
    ON call_sessions(created_by_user_id);
CREATE INDEX IF NOT EXISTS idx_call_participants_user
    ON call_participants(user_id, status);
CREATE INDEX IF NOT EXISTS idx_call_participants_session
    ON call_participants(call_session_id, status);
