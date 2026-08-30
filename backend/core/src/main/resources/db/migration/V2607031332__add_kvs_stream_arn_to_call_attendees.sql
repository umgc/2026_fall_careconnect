ALTER TABLE call_attendees
    ADD COLUMN IF NOT EXISTS kvs_stream_arn VARCHAR (512) NULL;

CREATE INDEX IF NOT EXISTS idx_call_attendees_kvs_stream_arn
    ON call_attendees(kvs_stream_arn);
