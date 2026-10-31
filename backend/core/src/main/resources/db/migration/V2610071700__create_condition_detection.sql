-- AI condition detection runs (per call + model status/queue) and screening flags.
-- AI condition detection: one durable run per (call, model) that doubles as the
-- per-model status the UI shows, plus the screening flags each run produced.
CREATE TABLE IF NOT EXISTS condition_detection_runs (
    id                BIGSERIAL PRIMARY KEY,
    call_id           VARCHAR(120) NOT NULL,
    patient_id        BIGINT       NOT NULL,
    patient_user_id   BIGINT       NOT NULL,
    model_id          VARCHAR(100) NOT NULL,
    input_kind        VARCHAR(30)  NOT NULL,
    config_version    VARCHAR(160),
    state             VARCHAR(20)  NOT NULL,
    skip_reason       VARCHAR(60),
    claim_token       UUID,
    claimed_until     TIMESTAMP,
    attempt_count     INTEGER      NOT NULL DEFAULT 0,
    next_attempt_at   TIMESTAMP    NOT NULL,
    last_error        TEXT,
    speech_seconds    DOUBLE PRECISION,
    created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at      TIMESTAMP,
    CONSTRAINT uq_condition_detection_runs_call_model UNIQUE (call_id, model_id)
);

-- Hibernate ddl-auto=update creates both tables from the entities before this patch runs,
-- so CREATE TABLE above is usually a no-op. Restate the defaults it cannot express.
ALTER TABLE condition_detection_runs
    ALTER COLUMN attempt_count SET DEFAULT 0,
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_condition_detection_runs_claim
    ON condition_detection_runs (next_attempt_at, claimed_until, id)
    WHERE state IN ('READY', 'RETRYABLE', 'CLAIMED', 'RUNNING');

CREATE INDEX IF NOT EXISTS idx_condition_detection_runs_patient
    ON condition_detection_runs (patient_id, created_at DESC);

CREATE TABLE IF NOT EXISTS condition_flags (
    id                BIGSERIAL PRIMARY KEY,
    run_id            BIGINT       NOT NULL,
    call_id           VARCHAR(120) NOT NULL,
    patient_id        BIGINT       NOT NULL,
    model_id          VARCHAR(100) NOT NULL,
    condition_name    VARCHAR(40)  NOT NULL,
    severity_level    INTEGER      NOT NULL,
    severity_label    VARCHAR(30)  NOT NULL,
    raw_score         DOUBLE PRECISION,
    evidence_summary  VARCHAR(500),
    created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_condition_flags_run
        FOREIGN KEY (run_id) REFERENCES condition_detection_runs (id) ON DELETE CASCADE
);

-- Same reason: a Hibernate-created condition_flags has no FK. The ledger applies this once.
ALTER TABLE condition_flags
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE condition_flags DROP CONSTRAINT IF EXISTS fk_condition_flags_run;
ALTER TABLE condition_flags
    ADD CONSTRAINT fk_condition_flags_run
        FOREIGN KEY (run_id) REFERENCES condition_detection_runs (id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_condition_flags_call
    ON condition_flags (call_id);

CREATE INDEX IF NOT EXISTS idx_condition_flags_patient
    ON condition_flags (patient_id, created_at DESC);
