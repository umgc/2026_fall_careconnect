-- System configuration key/value store
CREATE TABLE IF NOT EXISTS system_config (
    id BIGSERIAL PRIMARY KEY,
    config_key VARCHAR(255) NOT NULL UNIQUE,
    config_value TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by BIGINT,
    CONSTRAINT fk_system_config_updated_by
        FOREIGN KEY (updated_by) REFERENCES users (id) ON DELETE SET NULL
);

-- Seed default competency scale
INSERT INTO system_config (config_key, config_value)
VALUES
    ('competency_scale_min', '1'),
    ('competency_scale_max', '5'),
    ('competency_label_1', 'Total Assistance'),
    ('competency_label_2', 'Maximum Assistance'),
    ('competency_label_3', 'Moderate Assistance'),
    ('competency_label_4', 'Minimal Assistance'),
    ('competency_label_5', 'Independent')
ON CONFLICT (config_key) DO NOTHING;

