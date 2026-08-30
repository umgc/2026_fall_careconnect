-- Schema-patch twin of V2607251310.
ALTER TABLE user_files
    ADD COLUMN IF NOT EXISTS extracted_text TEXT NULL;
