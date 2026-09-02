-- Normalize billing schema and add platform-agnostic fields.
-- V1 created singular tables (subscription, payment); JPA uses subscriptions + payment.

DO
$$
BEGIN
    IF to_regclass('public.subscriptions') IS NULL AND to_regclass('public.subscription') IS NOT NULL THEN
ALTER TABLE subscription RENAME TO subscriptions;
END IF;
END $$;

CREATE TABLE IF NOT EXISTS subscriptions
(
    id
    BIGSERIAL
    PRIMARY
    KEY,
    user_id
    BIGINT
    NOT
    NULL
    REFERENCES
    users
(
    id
) ON DELETE CASCADE,
    plan_id BIGINT NOT NULL REFERENCES plan
(
    id
),
    status VARCHAR
(
    20
) DEFAULT 'ACTIVE',
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    current_period_end TIMESTAMP,
    stripe_customer_id VARCHAR
(
    255
),
    stripe_subscription_id VARCHAR
(
    255
),
    price_id VARCHAR
(
    255
)
    );

ALTER TABLE subscriptions
    ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR (255),
    ADD COLUMN IF NOT EXISTS stripe_subscription_id VARCHAR (255),
    ADD COLUMN IF NOT EXISTS price_id VARCHAR (255);

ALTER TABLE payment
    ADD COLUMN IF NOT EXISTS user_id BIGINT REFERENCES users (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS stripe_invoice_id VARCHAR (255);

ALTER TABLE payment
    ADD COLUMN IF NOT EXISTS platform VARCHAR (32),
    ADD COLUMN IF NOT EXISTS platform_purchase_token TEXT,
    ADD COLUMN IF NOT EXISTS platform_payer_id VARCHAR (255),
    ADD COLUMN IF NOT EXISTS external_transaction_id VARCHAR (255);

ALTER TABLE subscriptions
    ADD COLUMN IF NOT EXISTS platform VARCHAR (32),
    ADD COLUMN IF NOT EXISTS external_subscription_id VARCHAR (255),
    ADD COLUMN IF NOT EXISTS last_validated_at TIMESTAMP;

-- Note: nullable columns for backward compatibility with legacy Stripe-only rows.
