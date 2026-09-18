CREATE TABLE telemetry_events (
  id BIGSERIAL PRIMARY KEY,
  event_name VARCHAR(128) NOT NULL,
  event_time TIMESTAMPTZ NOT NULL DEFAULT now(),

  trace_id VARCHAR(64),
  span_id VARCHAR(32),

  device_info JSONB,
  details JSONB
);

CREATE INDEX idx_telemetry_events_time
  ON telemetry_events (event_time DESC);

CREATE INDEX idx_telemetry_events_name_time
  ON telemetry_events (event_name, event_time DESC);