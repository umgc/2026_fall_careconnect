CREATE INDEX IF NOT EXISTS idx_telemetry_events_time
  ON telemetry_events (event_time DESC);

CREATE INDEX IF NOT EXISTS idx_telemetry_events_name_time
  ON telemetry_events (event_name, event_time DESC);

CREATE INDEX IF NOT EXISTS idx_telemetry_events_trace_id
  ON telemetry_events (trace_id);