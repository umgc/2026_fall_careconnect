-- Add comments for documentation
COMMENT ON TABLE patient_medication IS 'Patient medication information including prescriptions and supplements';
COMMENT ON COLUMN patient_medication.patient_id IS 'Reference to the patient taking this medication';
COMMENT ON COLUMN patient_medication.medication_name IS 'Name of the medication or supplement';
COMMENT ON COLUMN patient_medication.dosage IS 'Dosage information (e.g., 10mg, 2 tablets)';
COMMENT ON COLUMN patient_medication.frequency IS 'How often to take (e.g., twice daily, every 8 hours)';
COMMENT ON COLUMN patient_medication.route IS 'Route of administration (oral, injection, topical, etc.)';
COMMENT ON COLUMN patient_medication.medication_type IS 'Type of medication (PRESCRIPTION, OVER_THE_COUNTER, SUPPLEMENT, HERBAL, EMERGENCY)';
COMMENT ON COLUMN patient_medication.prescribed_by IS 'Name of the prescribing healthcare provider';
COMMENT ON COLUMN patient_medication.prescribed_date IS 'Date when medication was prescribed';
COMMENT ON COLUMN patient_medication.start_date IS 'Date when patient started taking the medication';
COMMENT ON COLUMN patient_medication.end_date IS 'Date when medication should be stopped (null for ongoing)';
COMMENT ON COLUMN patient_medication.notes IS 'Additional instructions or notes about the medication';
COMMENT ON COLUMN patient_medication.is_active IS 'Whether the medication is currently active (for soft deletes)';

        -- Add missing columns to users table to match the User model
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS verification_token VARCHAR(255),
    ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR(255),
    ADD COLUMN IF NOT EXISTS last_login TIMESTAMP,
    ADD COLUMN IF NOT EXISTS profile_image_url VARCHAR(255);
