-- Add ma_number field to patient table for EVV tracking
ALTER TABLE patient ADD COLUMN IF NOT EXISTS ma_number VARCHAR(64);

-- Add unique constraint for ma_number to prevent duplicates
ALTER TABLE patient ADD CONSTRAINT unique_patient_ma_number UNIQUE (ma_number);

-- Add comment for documentation
COMMENT ON COLUMN patient.ma_number IS 'Medical Assistance Number for EVV compliance';

-- Add patient_id to evv_record table to link directly to patient
ALTER TABLE evv_record ADD COLUMN IF NOT EXISTS patient_id BIGINT;

-- Add foreign key constraint
ALTER TABLE evv_record ADD CONSTRAINT fk_evv_record_patient
    FOREIGN KEY (patient_id) REFERENCES patient(id) ON DELETE SET NULL;

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_evv_record_patient_id ON evv_record(patient_id);

-- Make participant_id nullable since we're moving to patient_id
ALTER TABLE evv_record ALTER COLUMN participant_id DROP NOT NULL;

-- Add comment
COMMENT ON COLUMN evv_record.patient_id IS 'Direct reference to patient receiving care - replaces participant_id';

-- Migrate existing EVV records from participant_id to patient_id
-- This migration only handles the data migration from evv_participant to patient

-- Update any existing records that have participant_id but no patient_id
-- This links EVV records to patients via the MA number
UPDATE evv_record
SET patient_id = (
    SELECT p.id
    FROM patient p
             JOIN evv_participant ep ON p.ma_number = ep.ma_number
    WHERE ep.id = evv_record.participant_id
)
WHERE patient_id IS NULL AND participant_id IS NOT NULL;