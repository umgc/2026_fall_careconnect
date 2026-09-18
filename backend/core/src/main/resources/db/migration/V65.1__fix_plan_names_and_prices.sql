-- V65__fix_plan_names_and_prices.sql
-- Consolidates plan data to match frontend product IDs and DataInitializer.
-- Removes legacy Stripe-era plans and ensures exactly three canonical plans exist.

-- Remove all legacy and duplicate plans
DELETE FROM plan;

-- Reset sequence
ALTER SEQUENCE plan_id_seq RESTART WITH 1;

-- Free Plan (tierId: free)
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (1, 'plan_free', 'Free Plan', 0, 'MONTH', TRUE);

-- Standard Monthly (tierId: standard_monthly)
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (2, 'plan_standard_monthly', 'Standard Monthly', 999, 'MONTH', TRUE);

-- Premium Monthly (tierId: premium_monthly)
INSERT INTO plan (id, code, name, price_cents, billing_period, is_active)
VALUES (3, 'plan_premium_monthly', 'Premium Monthly', 2999, 'MONTH', TRUE);

-- Reset sequence to continue from 4
ALTER SEQUENCE plan_id_seq RESTART WITH 4;
