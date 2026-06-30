-- WBS 3.15.6
-- see .\backend\core\src\main\java\com
--          \careconnect\model\safety\AiAuditLedger.java
-- NOTE: FKs are used incredibly inconsistently across the repo
--       and there's a potential bug with user deletion which matters
--       as audit records are dependent on the user table
--       No FKs are used for now in the AI audit 
-- TODO: Fix the immutability issues in V44 and V28?

CREATE TABLE ai_audit_ledger (
    id              BIGSERIAL       PRIMARY KEY,
    event_type      VARCHAR(50)     NOT NULL,   -- QUERY | RESPONSE | VALIDATION | CONFIRMATION
    actor_user_id   BIGINT,                     -- null for system events
    patient_id      BIGINT,                     -- null for events out of patient scope
    session_id      VARCHAR(128),               -- correlates the events from a session
    source_feature  VARCHAR(100)    NOT NULL,   -- ASK_AI | SUMMARY | CONFIRMATION_SERVICE | CAREGIVER_VISIBILITY
    payload         JSONB,                      -- event-specific text (the actual query/response/etc.)
    occurred_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_audit_ledger_actor       ON ai_audit_ledger(actor_user_id);
CREATE INDEX idx_ai_audit_ledger_patient     ON ai_audit_ledger(patient_id);
CREATE INDEX idx_ai_audit_ledger_event_type  ON ai_audit_ledger(event_type);
CREATE INDEX idx_ai_audit_ledger_occurred_at ON ai_audit_ledger(occurred_at);
CREATE INDEX idx_ai_audit_ledger_session     ON ai_audit_ledger(session_id);

-- Reuse the immutability trigger function from V44
CREATE TRIGGER tr_ai_audit_ledger_immutable
    BEFORE UPDATE OR DELETE ON ai_audit_ledger
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();
