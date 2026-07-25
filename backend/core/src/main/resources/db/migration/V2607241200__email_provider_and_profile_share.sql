-- Multi-provider email credentials + profile share tokens

ALTER TABLE email_credentials
    ADD COLUMN IF NOT EXISTS email_address VARCHAR(320),
    ADD COLUMN IF NOT EXISTS auth_mode VARCHAR(20) NOT NULL DEFAULT 'OAUTH',
    ADD COLUMN IF NOT EXISTS imap_host VARCHAR(255),
    ADD COLUMN IF NOT EXISTS imap_port INTEGER,
    ADD COLUMN IF NOT EXISTS imap_username VARCHAR(320);

CREATE INDEX IF NOT EXISTS idx_email_credentials_user_id
    ON email_credentials (user_id);

CREATE TABLE IF NOT EXISTS profile_share_token
(
    id                  BIGSERIAL PRIMARY KEY,
    version             BIGINT       NOT NULL DEFAULT 0,
    token_lookup        VARCHAR(32)  NOT NULL,
    token_hash          VARCHAR(255) NOT NULL,
    patient_user_id     BIGINT       NOT NULL,
    patient_id          BIGINT       NOT NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_by_user_id  BIGINT       NOT NULL,
    expires_at          TIMESTAMP    NOT NULL,
    revoked_by_user_id  BIGINT,
    revoked_at          TIMESTAMP,
    revoke_reason       VARCHAR(500),
    created_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_profile_share_patient_user
        FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_profile_share_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_profile_share_revoked_by
        FOREIGN KEY (revoked_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_share_token_lookup
    ON profile_share_token (token_lookup);
CREATE INDEX IF NOT EXISTS idx_profile_share_patient_user
    ON profile_share_token (patient_user_id);
CREATE INDEX IF NOT EXISTS idx_profile_share_status
    ON profile_share_token (status);

-- Professional caregiver practice / organization fields
ALTER TABLE caregiver
    ADD COLUMN IF NOT EXISTS organization VARCHAR(255),
    ADD COLUMN IF NOT EXISTS practice_name VARCHAR(255);
