CREATE TABLE IF NOT EXISTS incident_reports (
    id BIGSERIAL PRIMARY KEY,
    client_id BIGINT NOT NULL,
    caregiver_id BIGINT NOT NULL,
    incident_type VARCHAR(50) NOT NULL CHECK (incident_type IN
        ('FALL', 'BEHAVIORAL_CRISIS', 'MEDICAL_EVENT', 'ELOPEMENT', 'SELF_HARM', 'PROPERTY_DAMAGE', 'OTHER')),
    occurred_at TIMESTAMP NOT NULL,
    location TEXT NOT NULL,
    trigger_notes TEXT,
    outcome TEXT NOT NULL,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_incident_reports_client
        FOREIGN KEY (client_id) REFERENCES patient (id) ON DELETE CASCADE,
    CONSTRAINT fk_incident_reports_caregiver
        FOREIGN KEY (caregiver_id) REFERENCES caregiver (id) ON DELETE RESTRICT,
    CONSTRAINT fk_incident_reports_created_by
        FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS incident_actions (
    id BIGSERIAL PRIMARY KEY,
    incident_report_id BIGINT NOT NULL,
    action_taken TEXT NOT NULL,
    CONSTRAINT fk_incident_actions_report
        FOREIGN KEY (incident_report_id) REFERENCES incident_reports (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_incident_reports_client_occurred_at
    ON incident_reports (client_id, occurred_at DESC);

