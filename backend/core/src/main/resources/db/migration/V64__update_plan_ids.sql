-- Update subscription plans to have consistent IDs for frontend
-- This ensures frontend tierId mappings match database Plan IDs

-- Delete existing plans (if any)
DELETE FROM plan;

-- Reset sequence to start at 1
ALTER SEQUENCE plan_id_seq RESTART WITH 1;

-- Insert Free Plan with ID 1
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (1, 'plan_free', 'Free Plan', 0, 'MONTH', TRUE);

-- Insert Standard Plan with ID 2
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (2, 'plan_standard_monthly', 'Standard Plan', 999, 'MONTH', TRUE);

-- Insert Premium Plan with ID 3
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (3, 'plan_premium_monthly', 'Premium Plan', 2999, 'MONTH', TRUE);

-- Reset sequence to continue from 4
ALTER SEQUENCE plan_id_seq RESTART WITH 4;
