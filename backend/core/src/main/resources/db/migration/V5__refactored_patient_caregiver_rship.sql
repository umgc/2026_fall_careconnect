-- V5: Refactored patient-caregiver relationship using new linking table
-- This replaces the direct foreign key relationship with a more flexible linking system

-- Create the new patient_caregiver_relationship table
CREATE TABLE IF NOT EXISTS patient_caregiver
(
    id                BIGSERIAL PRIMARY KEY,
    patient_id        BIGINT NOT NULL,
    caregiver_user_id BIGINT NOT NULL,
    relationship_type VARCHAR(50) DEFAULT 'PRIMARY',
    created_at        TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    status            VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
    notes             TEXT,
    FOREIGN KEY (patient_id) REFERENCES patient (id) ON DELETE CASCADE,
    FOREIGN KEY (caregiver_user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_patient_caregiver_patient ON patient_caregiver (patient_id);
CREATE INDEX IF NOT EXISTS idx_patient_caregiver_caregiver ON patient_caregiver (caregiver_user_id);
CREATE INDEX IF NOT EXISTS idx_patient_caregiver_status ON patient_caregiver (status);

-- Create trigger for automatic updated_at updates
CREATE OR REPLACE FUNCTION update_patient_caregiver_updated_at()
    RETURNS TRIGGER AS
$$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_patient_caregiver_relationship_updated_at
    BEFORE UPDATE
    ON patient_caregiver
    FOR EACH ROW
EXECUTE FUNCTION update_patient_caregiver_updated_at();