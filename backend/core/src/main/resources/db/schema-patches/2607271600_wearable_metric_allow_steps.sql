-- Allow STEPS in wearable_metric check constraint.
-- Local DBs created before V2607011802 still reject STEPS, which poisons
-- wearable ingest transactions (UnexpectedRollbackException → HTTP 500).

ALTER TABLE wearable_metric
DROP CONSTRAINT IF EXISTS wearable_metric_metric_check;

ALTER TABLE wearable_metric
ADD CONSTRAINT wearable_metric_metric_check
CHECK (
    metric IN (
        'HEART_RATE',
        'SPO2',
        'TEMPERATURE',
        'BLOOD_PRESSURE_SYS',
        'BLOOD_PRESSURE_DIA',
        'WEIGHT',
        'STEPS'
    )
);
