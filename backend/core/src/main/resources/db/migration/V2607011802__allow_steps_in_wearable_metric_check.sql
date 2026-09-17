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
