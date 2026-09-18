-- Task 2.4 schema patch (ScriptUtils-safe; no dollar-quoted blocks).
CREATE TABLE IF NOT EXISTS consent_grants (
  id BIGSERIAL PRIMARY KEY,
  patient_user_id BIGINT NOT NULL,
  grantee_user_id BIGINT NOT NULL,
  grantee_role VARCHAR(32) NOT NULL,
  scope VARCHAR(64) NOT NULL DEFAULT 'AI_RETRIEVAL',
  status VARCHAR(24) NOT NULL,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NULL,
  revoked_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consent_grants_lookup
  ON consent_grants (patient_user_id, grantee_user_id, scope, status);
