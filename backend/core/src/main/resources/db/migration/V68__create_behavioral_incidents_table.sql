CREATE TABLE IF NOT EXISTS behavioral_incidents
(
    id
    BIGSERIAL
    PRIMARY
    KEY,
    client_id
    BIGINT
    NOT
    NULL,
    caregiver_id
    BIGINT
    NOT
    NULL,
    observed_behavior
    TEXT
    NOT
    NULL,
    occurred_at
    TIMESTAMP
    NOT
    NULL,
    trigger_notes
    TEXT,
    created_by
    BIGINT
    NOT
    NULL,
    created_at
    TIMESTAMP
    DEFAULT
    CURRENT_TIMESTAMP
    NOT
    NULL,
    CONSTRAINT
    fk_behavioral_incidents_client
    FOREIGN
    KEY
(
    client_id
) REFERENCES patient
(
    id
) ON DELETE CASCADE,
    CONSTRAINT fk_behavioral_incidents_caregiver
    FOREIGN KEY
(
    caregiver_id
) REFERENCES caregiver
(
    id
)
  ON DELETE RESTRICT,
    CONSTRAINT fk_behavioral_incidents_created_by
    FOREIGN KEY
(
    created_by
) REFERENCES users
(
    id
)
  ON DELETE RESTRICT
    );

CREATE INDEX IF NOT EXISTS idx_behavioral_incidents_client_occurred_at
    ON behavioral_incidents (client_id, occurred_at DESC);

DROP TRIGGER IF EXISTS tr_behavioral_incidents_immutable ON behavioral_incidents;
CREATE TRIGGER tr_behavioral_incidents_immutable
    BEFORE UPDATE OR
DELETE
ON behavioral_incidents
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();

