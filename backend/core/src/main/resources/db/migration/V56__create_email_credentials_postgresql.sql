-- Create email_credentials table for PostgreSQL
CREATE TABLE IF NOT EXISTS email_credentials (
    id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(191) NOT NULL,
    provider VARCHAR(20) NOT NULL,
    access_token_enc TEXT,
    refresh_token_enc TEXT,
    expires_at TIMESTAMP NULL
);

CREATE INDEX IF NOT EXISTS idx_email_cred ON email_credentials (user_id, provider);

-- Create usps_digest_cache table for PostgreSQL
CREATE TABLE IF NOT EXISTS usps_digest_cache (
    id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(191) NOT NULL,
    payload_json TEXT NOT NULL,
    digest_date TIMESTAMP NULL,
    expires_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_usps_cache ON usps_digest_cache (user_id, expires_at);