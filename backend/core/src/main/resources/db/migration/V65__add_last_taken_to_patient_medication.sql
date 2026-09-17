ALTER TABLE patient_medication
    ADD COLUMN IF NOT EXISTS last_taken TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_patient_medication_last_taken
    ON patient_medication(patient_id, last_taken DESC);

COMMENT ON COLUMN patient_medication.last_taken IS
    'UTC timestamp representing when the medication was last marked as taken';
