CREATE TABLE IF NOT EXISTS vital_alert_event (
  id BIGSERIAL PRIMARY KEY,
  patient_id BIGINT NOT NULL,
  patient_user_id BIGINT NOT NULL,
  metric_type VARCHAR(64) NOT NULL,
  measured_value VARCHAR(64) NOT NULL,
  alert_level VARCHAR(16) NOT NULL,
  status VARCHAR(32) NOT NULL,
  recipient_count INTEGER NOT NULL DEFAULT 0,
  success_count INTEGER NOT NULL DEFAULT 0,
  failure_count INTEGER NOT NULL DEFAULT 0,
  failure_reason VARCHAR(255),
  occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_vital_alert_event_patient_occurred_at
  ON vital_alert_event (patient_id, occurred_at DESC);
