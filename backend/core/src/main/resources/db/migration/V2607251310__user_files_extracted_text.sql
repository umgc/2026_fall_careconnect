-- Extracted document text for Ask AI indexing (beyond description-only captions).
ALTER TABLE user_files
    ADD COLUMN IF NOT EXISTS extracted_text TEXT NULL;
