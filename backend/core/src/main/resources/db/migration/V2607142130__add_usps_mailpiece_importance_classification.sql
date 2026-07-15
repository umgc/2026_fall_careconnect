-- V2607142130__add_usps_mailpiece_importance_classification.sql
--
-- Task 3.14.6 (#123) — Rule-based + AI-assist importance classification
-- with recorded reasoning on usps_mailpiece (depends on V2607142100 / #122).
--
-- Ownership: Team E (USPS / mail agent).

ALTER TABLE usps_mailpiece
    ADD COLUMN IF NOT EXISTS importance_level VARCHAR(16) NULL,
    ADD COLUMN IF NOT EXISTS importance_confidence NUMERIC(3, 2) NULL,
    ADD COLUMN IF NOT EXISTS classification_method VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS classification_engine VARCHAR(128) NULL,
    ADD COLUMN IF NOT EXISTS importance_reasoning TEXT NULL,
    ADD COLUMN IF NOT EXISTS importance_category VARCHAR(40) NULL,
    ADD COLUMN IF NOT EXISTS classified_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS idx_usps_mailpiece_patient_importance
    ON usps_mailpiece (patient_id, importance_level, digest_date);

COMMENT ON COLUMN usps_mailpiece.importance_level IS
    'Importance tier: HIGH, MODERATE, LOW, or UNKNOWN (Task 3.14.6).';

COMMENT ON COLUMN usps_mailpiece.importance_confidence IS
    'Classifier confidence in [0.00, 1.00].';

COMMENT ON COLUMN usps_mailpiece.classification_method IS
    'How the tier was chosen: RULES, AI, or HYBRID.';

COMMENT ON COLUMN usps_mailpiece.classification_engine IS
    'Engine id, e.g. rules:v1 or aws_bedrock:amazon.nova-lite-v1:0.';

COMMENT ON COLUMN usps_mailpiece.importance_reasoning IS
    'Human-readable recorded rationale for the classification decision.';

COMMENT ON COLUMN usps_mailpiece.importance_category IS
    'Optional topical category: MEDICAL, FINANCIAL, LEGAL, ADMINISTRATIVE, MARKETING, OTHER.';
