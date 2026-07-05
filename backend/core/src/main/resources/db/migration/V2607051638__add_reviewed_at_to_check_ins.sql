ALTER TABLE check_ins
    ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_check_ins_patient_reviewed
    ON check_ins(patient_id, reviewed_at);
