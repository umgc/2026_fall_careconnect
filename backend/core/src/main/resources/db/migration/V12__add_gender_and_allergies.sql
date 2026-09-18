COMMENT ON COLUMN patient.gender IS 'Patient gender (MALE, FEMALE, OTHER, PREFER_NOT_TO_SAY)';
COMMENT ON COLUMN caregiver.gender IS 'Caregiver gender (MALE, FEMALE, OTHER, PREFER_NOT_TO_SAY)';


-- Add comments for documentation
COMMENT ON TABLE patient_allergy IS 'Patient allergy information including allergens, reactions, and severity';
COMMENT ON COLUMN patient_allergy.patient_id IS 'Reference to the patient who has this allergy';
COMMENT ON COLUMN patient_allergy.allergen IS 'Name of the allergen (e.g., Peanuts, Penicillin, Latex)';
COMMENT ON COLUMN patient_allergy.allergy_type IS 'Type of allergy (FOOD, MEDICATION, ENVIRONMENTAL, CONTACT, SEASONAL, OTHER)';
COMMENT ON COLUMN patient_allergy.severity IS 'Severity level (MILD, MODERATE, SEVERE, LIFE_THREATENING)';
COMMENT ON COLUMN patient_allergy.reaction IS 'Description of allergic reaction symptoms';
COMMENT ON COLUMN patient_allergy.notes IS 'Additional notes from healthcare providers';
COMMENT ON COLUMN patient_allergy.diagnosed_date IS 'When the allergy was first diagnosed';
COMMENT ON COLUMN patient_allergy.is_active IS 'Whether the allergy is currently active (for soft deletes)';
