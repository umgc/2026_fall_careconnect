-- Audit hardening: add created_by to tables that were missing it (user attribution from session only).

-- activity_log: who created this log record (audit)
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'activity_log'
    ) THEN
        ALTER TABLE activity_log ADD COLUMN IF NOT EXISTS created_by BIGINT;
        UPDATE activity_log SET created_by = caregiver_user_id WHERE created_by IS NULL;
        ALTER TABLE activity_log ALTER COLUMN created_by SET NOT NULL;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints
            WHERE constraint_name = 'fk_activity_log_created_by'
        ) THEN
            ALTER TABLE activity_log
                ADD CONSTRAINT fk_activity_log_created_by
                FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT;
        END IF;
    END IF;
END $$;

-- client_events: who created this event record (audit)
ALTER TABLE client_events ADD COLUMN IF NOT EXISTS created_by BIGINT;
UPDATE client_events ce SET created_by = c.user_id
FROM caregiver c WHERE ce.caregiver_id = c.id AND ce.created_by IS NULL;
-- Fallback for any orphan rows (caregiver deleted): use first admin/user if any
UPDATE client_events SET created_by = (SELECT id FROM users ORDER BY id LIMIT 1)
WHERE created_by IS NULL AND EXISTS (SELECT 1 FROM users LIMIT 1);
ALTER TABLE client_events ALTER COLUMN created_by SET NOT NULL;
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_client_events_created_by'
    ) THEN
        ALTER TABLE client_events
            ADD CONSTRAINT fk_client_events_created_by
            FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT;
    END IF;
END $$;

-- incident_actions: who created this action record (audit; usually same as report creator)
ALTER TABLE incident_actions ADD COLUMN IF NOT EXISTS created_by BIGINT;
UPDATE incident_actions ia SET created_by = ir.created_by
FROM incident_reports ir WHERE ia.incident_report_id = ir.id AND ia.created_by IS NULL;
ALTER TABLE incident_actions ALTER COLUMN created_by SET NOT NULL;
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_incident_actions_created_by'
    ) THEN
        ALTER TABLE incident_actions
            ADD CONSTRAINT fk_incident_actions_created_by
            FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT;
    END IF;
END $$;
