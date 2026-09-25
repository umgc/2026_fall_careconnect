-- Schema-patch twin of V2607251300 (ScriptUtils-safe).
-- Patient-scoped unique open hold; drop legacy unscoped index if present.
DROP INDEX IF EXISTS uq_ai_held_item_open_surface_hash;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ai_held_item_open_patient_surface_hash
  ON ai_held_item (patient_id, source_surface, query_text_hash)
  WHERE status = 'PENDING_REVIEW'
    AND query_text_hash IS NOT NULL;
