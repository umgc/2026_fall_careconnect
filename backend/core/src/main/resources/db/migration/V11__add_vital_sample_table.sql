-- Add comments for documentation
COMMENT ON TABLE vital_sample IS 'Unified storage for all patient vital signs and health measurements';
COMMENT ON COLUMN vital_sample.patient_id IS 'Reference to the patient this vital sample belongs to';
COMMENT ON COLUMN vital_sample.timestamp IS 'When this vital measurement was taken';
COMMENT ON COLUMN vital_sample.heart_rate IS 'Heart rate in beats per minute (BPM)';
COMMENT ON COLUMN vital_sample.spo2 IS 'Blood oxygen saturation percentage (SpO2)';
COMMENT ON COLUMN vital_sample.systolic IS 'Systolic blood pressure in mmHg';
COMMENT ON COLUMN vital_sample.diastolic IS 'Diastolic blood pressure in mmHg';
COMMENT ON COLUMN vital_sample.weight IS 'Patient weight in kilograms';
COMMENT ON COLUMN vital_sample.mood_value IS 'Mood rating on scale 1-10 (1=very bad, 10=excellent)';
COMMENT ON COLUMN vital_sample.pain_value IS 'Pain level on scale 1-10 (1=no pain, 10=severe pain)';
