-- Insert subscription plans for the application
-- This migration adds two default plans: Standard Plan and Premium Plan

-- Check if the plan table exists, and create it if it doesn't
CREATE TABLE IF NOT EXISTS plan (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(100) NOT NULL,
  price_cents INT NOT NULL,
  billing_period VARCHAR(20) DEFAULT 'MONTH',
  is_active BOOLEAN DEFAULT TRUE,
  UNIQUE (code),
  CONSTRAINT plan_chk_1 CHECK ((price_cents >= 0))
);

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
