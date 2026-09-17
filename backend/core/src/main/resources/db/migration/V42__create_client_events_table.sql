CREATE TABLE IF NOT EXISTS client_events (
    id BIGSERIAL PRIMARY KEY,
    client_id BIGINT NOT NULL,
    caregiver_id BIGINT NOT NULL,
    activity_id BIGINT NOT NULL,
    tapped_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_client_events_client
        FOREIGN KEY (client_id) REFERENCES patient (id) ON DELETE CASCADE,
    CONSTRAINT fk_client_events_caregiver
        FOREIGN KEY (caregiver_id) REFERENCES caregiver (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_client_events_client_tapped_at
    ON client_events (client_id, tapped_at DESC);

