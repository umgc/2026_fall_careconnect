ALTER TABLE lagging_schema
    ADD COLUMN IF NOT EXISTS patient_id BIGINT;
UPDATE lagging_schema
SET patient_id = 42
WHERE patient_id IS NULL;
