-- Task 3.14.9 / #126: credential revocation + sync halt fields for email OAuth.
ALTER TABLE email_credentials
    ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE';

ALTER TABLE email_credentials
    ADD COLUMN IF NOT EXISTS sync_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE email_credentials
    ADD COLUMN IF NOT EXISTS last_error VARCHAR(512);

ALTER TABLE email_credentials
    ADD COLUMN IF NOT EXISTS last_error_at TIMESTAMPTZ;

ALTER TABLE email_credentials
    ADD COLUMN IF NOT EXISTS reauth_notified_at TIMESTAMPTZ;
