CREATE TABLE IF NOT EXISTS activity_log (
    id BIGSERIAL PRIMARY KEY,
    client_id BIGINT NOT NULL,
    activity_id BIGINT NOT NULL,
    caregiver_user_id BIGINT NOT NULL,
    competency_score INT NOT NULL,
    satisfaction_rating INT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_activity_log_client
        FOREIGN KEY (client_id) REFERENCES patient (id) ON DELETE CASCADE,
    CONSTRAINT fk_activity_log_caregiver_user
        FOREIGN KEY (caregiver_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_activity_log_client_created_at
    ON activity_log (client_id, created_at DESC);

