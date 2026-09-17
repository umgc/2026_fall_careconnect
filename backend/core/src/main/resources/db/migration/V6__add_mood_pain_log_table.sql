-- V6__add_mood_pain_log_table.sql
-- Add mood and pain logging functionality for patients

CREATE TABLE mood_pain_log (
    id BIGSERIAL PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    mood_value INT NOT NULL CHECK (mood_value >= 1 AND mood_value <= 10),
    pain_value INT NOT NULL CHECK (pain_value >= 1 AND pain_value <= 10),
    note TEXT,
    timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (patient_id) REFERENCES patient(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_mood_pain_patient_timestamp ON mood_pain_log(patient_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_mood_pain_timestamp ON mood_pain_log(timestamp);

-- Delete any existing plans with the same codes to avoid conflicts
DELETE FROM plan WHERE code IN ('plan_SbkhH3AATKabKy', 'plan_SbkhIoC5wy5iwB');

-- Insert Standard Plan
INSERT INTO plan (code, name, price_cents, billing_period, is_active)
VALUES ('plan_SbkhH3AATKabKy', 'Standard Plan', 2000, 'MONTH', TRUE)
ON CONFLICT (code) DO NOTHING;

-- Insert Premium Plan
INSERT INTO plan (code, name, price_cents, billing_period, is_active)
VALUES ('plan_SbkhIoC5wy5iwB', 'Premium Plan', 3000, 'MONTH', TRUE)
ON CONFLICT (code) DO NOTHING;

-- Insert a mapping for the existing subscription (if price_1RmqWxELoozGI1YxQql5rsvN exists in any subscription)
-- This ensures existing subscriptions with this price ID are linked to the Premium Plan
INSERT INTO plan (code, name, price_cents, billing_period, is_active)
VALUES ('price_1RmqWxELoozGI1YxQql5rsvN', 'Premium Plan', 3000, 'MONTH', TRUE)
ON CONFLICT (code) DO NOTHING;
