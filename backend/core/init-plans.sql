-- Manual SQL script to insert subscription plans
-- Run this if plans are missing or IDs don't match frontend expectations

-- First, check and delete any existing plans (adjust as needed)
DELETE FROM plan WHERE code IN ('plan_free', 'plan_standard_monthly', 'plan_premium_monthly');

-- Insert Free Plan with ID 1
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (1, 'plan_free', 'Free Plan', 0, 'MONTH', TRUE)
ON CONFLICT DO NOTHING;

-- Insert Standard Monthly Plan with ID 2  
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (2, 'plan_standard_monthly', 'Standard Monthly', 999, 'MONTH', TRUE)
ON CONFLICT DO NOTHING;

-- Insert Premium Monthly Plan with ID 3
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (3, 'plan_premium_monthly', 'Premium Monthly', 2999, 'MONTH', TRUE)
ON CONFLICT DO NOTHING;

-- Verify inserted plans
SELECT id, code,name, price_cents FROM plan ORDER BY id;
