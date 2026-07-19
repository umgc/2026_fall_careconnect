ALTER TABLE telemetry_events
  ADD COLUMN IF NOT EXISTS session_id VARCHAR(64);

CREATE INDEX IF NOT EXISTS idx_telemetry_events_session_id_time
  ON telemetry_events (session_id, event_time DESC)
  WHERE session_id IS NOT NULL;
