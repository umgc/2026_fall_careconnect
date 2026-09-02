-- Schema-patch twin of V2607250100 (ScriptUtils-safe; no dollar-quoted blocks).
-- Collapse duplicate ACTIVE grants, then enforce uniqueness.

UPDATE consent_grants g
SET status     = 'REVOKED',
    revoked_at = COALESCE(g.revoked_at, NOW()),
    updated_at = NOW() FROM (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY patient_user_id, grantee_user_id, scope
           ORDER BY id
         ) AS rn
  FROM consent_grants
  WHERE status = 'ACTIVE'
) d
WHERE g.id = d.id
  AND d.rn
    > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_consent_grants_active
    ON consent_grants (patient_user_id, grantee_user_id, scope)
    WHERE status = 'ACTIVE';
