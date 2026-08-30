ALTER TABLE call_sessions
DROP
CONSTRAINT IF EXISTS ck_call_sessions_status;
ALTER TABLE call_sessions
    ADD CONSTRAINT ck_call_sessions_status
        CHECK (status IN ('CREATED', 'ACTIVE', 'TERMINATING', 'ENDED', 'CANCELLED'));

ALTER TABLE call_participants
DROP
CONSTRAINT IF EXISTS ck_call_participants_status;
ALTER TABLE call_participants
    ADD CONSTRAINT ck_call_participants_status
        CHECK (status IN ('INVITED', 'JOINED', 'LEFT', 'DECLINED', 'EXPIRED'));

DO
$$
BEGIN
    IF
NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_call_sessions_scheduled_visit' AND contype = 'f'
    ) THEN
ALTER TABLE call_sessions
    ADD CONSTRAINT fk_call_sessions_scheduled_visit
        FOREIGN KEY (scheduled_visit_id) REFERENCES scheduled_visits (id);
END IF;
END $$;
