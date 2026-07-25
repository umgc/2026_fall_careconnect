-- Add practice/organization to caregiver professional embed columns
ALTER TABLE caregiver
    ADD COLUMN IF NOT EXISTS organization VARCHAR(255);
