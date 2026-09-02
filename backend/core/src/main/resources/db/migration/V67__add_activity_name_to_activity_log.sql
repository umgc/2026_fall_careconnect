ALTER TABLE activity_log
    ADD COLUMN IF NOT EXISTS activity_name VARCHAR (255);

-- V43 runs before activity_log exists; apply created_by audit here after table creation (V66).
ALTER TABLE activity_log
    ADD COLUMN IF NOT EXISTS created_by BIGINT;
UPDATE activity_log
SET created_by = caregiver_user_id
WHERE created_by IS NULL;
ALTER TABLE activity_log
    ALTER COLUMN created_by SET NOT NULL;
DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_activity_log_created_by'
    ) THEN
ALTER TABLE activity_log
    ADD CONSTRAINT fk_activity_log_created_by
        FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT;
END IF;
END $$;

DROP TRIGGER IF EXISTS tr_activity_log_immutable ON activity_log;
CREATE TRIGGER tr_activity_log_immutable
    BEFORE UPDATE OR
DELETE
ON activity_log
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();
