-- Add patient_id column to family_member_link table for denormalization
-- This will improve query performance by avoiding joins

-- Add the patient_id column
ALTER TABLE family_member_link
    ADD COLUMN patient_id BIGINT;

-- -- Populate the patient_id column from existing data
-- UPDATE family_member_link fml
-- SET patient_id = (
--     SELECT p.id 
--     FROM patient p 
--     WHERE p.user_id = fml.patient_user_id
-- );

-- Add index for faster queries
CREATE INDEX idx_family_member_link_patient_id ON family_member_link(patient_id);

-- Add foreign key constraint
ALTER TABLE family_member_link
    ADD CONSTRAINT fk_family_member_link_patient_id
        FOREIGN KEY (patient_id) REFERENCES patient(id);

-- Add unique constraint to prevent duplicate family member-patient links
-- This ensures the same family member (by user) cannot be linked to the same patient multiple times
ALTER TABLE family_member_link
    ADD CONSTRAINT uk_family_member_link_unique
        UNIQUE (family_user_id, patient_user_id);

ALTER TABLE family_member_link
    ADD CONSTRAINT uk_family_member_link_patient_unique
        UNIQUE (family_user_id, patient_id);

-- Add column comment (PostgreSQL syntax)
COMMENT ON COLUMN family_member_link.patient_id IS 'Denormalized patient ID for faster queries without joins';