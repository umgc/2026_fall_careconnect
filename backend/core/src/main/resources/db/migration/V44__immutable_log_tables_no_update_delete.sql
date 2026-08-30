-- Enforce immutability: prevent UPDATE and DELETE on log/incident tables.
-- INSERT-only; records are append-only for audit integrity.

CREATE
OR REPLACE FUNCTION reject_update_delete_immutable()
RETURNS TRIGGER AS $$
BEGIN
    RAISE
EXCEPTION 'Updates and deletes are not allowed on immutable log/incident tables (%).', TG_TABLE_NAME;
END;
$$
LANGUAGE plpgsql;

-- incident_reports
DROP TRIGGER IF EXISTS tr_incident_reports_immutable ON incident_reports;
CREATE TRIGGER tr_incident_reports_immutable
    BEFORE UPDATE OR
DELETE
ON incident_reports
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();

-- incident_actions
DROP TRIGGER IF EXISTS tr_incident_actions_immutable ON incident_actions;
CREATE TRIGGER tr_incident_actions_immutable
    BEFORE UPDATE OR
DELETE
ON incident_actions
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();

-- client_events
DROP TRIGGER IF EXISTS tr_client_events_immutable ON client_events;
CREATE TRIGGER tr_client_events_immutable
    BEFORE UPDATE OR
DELETE
ON client_events
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();

-- activity_log and behavioral_incidents are created in V66/V68; triggers applied there.
