ALTER TABLE patient
  ADD COLUMN IF NOT EXISTS is_alexa_linked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS alexa_refresh_token VARCHAR(500),
  ADD COLUMN IF NOT EXISTS alexa_refresh_token_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS alexa_refresh_token_created_at TIMESTAMPTZ;
