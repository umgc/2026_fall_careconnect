-- CC-12 Emergency Identity & Care Passport, Increment 2: the code behind the patient's QR.
--
-- NOTHING EXECUTES THIS FILE. Flyway is disabled in every profile: Hibernate ddl-auto=update
-- creates the table from EmergencyPassportToken, and SchemaPatchRunner.applyEmergencyPassportPatches()
-- adds the indexes, the foreign key and the TIMESTAMPTZ conversion on every boot. If this file ever
-- disagrees with the entity or the runner, the running database follows them.
--
-- Follows invite_token: the raw token is never stored. token_lookup is its non-secret 16-character
-- prefix; token_hash is a BCrypt hash of the whole token. There is no expires_at: the QR is meant to
-- live on a lock screen, so revocation, not a timer, is the safety control.

CREATE TABLE IF NOT EXISTS emergency_passport_token (
    id              BIGSERIAL    PRIMARY KEY,
    patient_id      BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    token_lookup    VARCHAR(32)  NOT NULL,
    token_hash      VARCHAR(255) NOT NULL,
    status          VARCHAR(20)  NOT NULL,   -- ACTIVE / REVOKED
    revoked_at      TIMESTAMPTZ,
    last_scanned_at TIMESTAMPTZ,             -- the only scan record for M4
    created_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ,
    CONSTRAINT uq_emergency_passport_token_lookup UNIQUE (token_lookup)
);

CREATE INDEX IF NOT EXISTS idx_emergency_passport_token_patient
    ON emergency_passport_token (patient_id);

-- Making a new code revokes the old one; this makes "one live code per patient" a database fact
-- rather than something every caller has to get right.
CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_passport_token_one_active
    ON emergency_passport_token (patient_id) WHERE status = 'ACTIVE';
