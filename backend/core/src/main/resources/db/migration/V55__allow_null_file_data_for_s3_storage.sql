-- user_files may have been JPA-created on older installs; ensure table exists before S3 nullability change.
CREATE TABLE IF NOT EXISTS user_files (
    id                BIGSERIAL PRIMARY KEY,
    filename          VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    content_type      VARCHAR(255),
    file_size         BIGINT,
    file_data         BYTEA,
    owner_id          BIGINT NOT NULL,
    owner_type        VARCHAR(32) NOT NULL,
    file_category     VARCHAR(64) NOT NULL,
    patient_id        BIGINT,
    storage_type      VARCHAR(32) NOT NULL DEFAULT 'DATABASE',
    s3_path           VARCHAR(500),
    description       TEXT,
    uploaded_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP,
    is_active         BOOLEAN NOT NULL DEFAULT TRUE
);

-- Allow file_data to be NULL when files are stored in S3 (not in the database).
ALTER TABLE user_files ALTER COLUMN file_data DROP NOT NULL;
