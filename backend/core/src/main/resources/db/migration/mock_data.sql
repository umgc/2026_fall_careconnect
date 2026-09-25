-- ============================================
-- CareConnect Mock Data Generation - Fixed Schema
-- 1 Patient, 1 Caregiver, 1 Family Member, 1 Admin
-- Corrected to match actual entity schemas
-- ============================================

-- ============================================
-- 1. USERS TABLE - Match current schema (no name, last_login_date instead of last_login)
-- ============================================

-- Patient User
INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at) VALUES
('patient@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'PATIENT', 'ACTIVE', '2024-06-16', '2024-06-15 10:00:00');

-- Caregiver User
INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at) VALUES
('caregiver@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'CAREGIVER', 'ACTIVE', '2024-05-02', '2024-05-01 09:00:00');

-- Doctor Caregiver User (for patient-facing provider profile and call tests)
INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at)
SELECT 'sarah.mitchell@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'CAREGIVER', 'ACTIVE', '2024-05-05', '2024-05-05 09:00:00'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'sarah.mitchell@careconnect.com');

-- Family Member User
INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at) VALUES
('family@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'FAMILY_MEMBER', 'ACTIVE', '2024-07-11', '2024-07-10 16:00:00');

-- Admin User
INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at)
SELECT 'admin@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'ADMIN', 'ACTIVE', '2024-07-01', '2024-07-01 09:00:00'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@careconnect.com');

-- ============================================
-- 2. PATIENT TABLE - Use embedded Address fields (line1, line2, not address_line1/2)
-- ============================================

INSERT INTO patient (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender) VALUES
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'Mary', 'Johnson', '1958-03-15', 'patient@careconnect.com', '555-0101', '123 Maple Street', 'Apt 4B', 'Falls Chrurch', 'VA', '22046', 'FEMALE');

-- ============================================
-- 3. CAREGIVER TABLE - Use embedded Address fields (line1, line2, not address_line1/2)
-- ============================================

INSERT INTO caregiver (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender, caregiver_type) VALUES
((SELECT id FROM users WHERE email = 'caregiver@careconnect.com'), 'Jennifer', 'Smith', '1985-09-12', 'caregiver@careconnect.com', '555-0200', '321 Healthcare Plaza', 'Suite 200', 'Falls Chrurch', 'VA', '22046', 'FEMALE', 'RN');

INSERT INTO caregiver (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender, caregiver_type)
SELECT
    (SELECT id FROM users WHERE email = 'sarah.mitchell@careconnect.com'),
    'Sarah',
    'Mitchel',
    '1978-04-21',
    'sarah.mitchell@careconnect.com',
    '(555) 123-4567',
    '400 Medical Center Drive',
    'Suite 120',
    'Falls Chrurch',
    'VA',
    '22046',
    'FEMALE',
    'MD'
WHERE NOT EXISTS (
    SELECT 1
    FROM caregiver c
    JOIN users u ON c.user_id = u.id
    WHERE u.email = 'sarah.mitchell@careconnect.com'
);

-- ============================================
-- 4. FAMILY_MEMBER TABLE
-- ============================================

INSERT INTO family_member (user_id, first_name, last_name, email, phone) VALUES
((SELECT id FROM users WHERE email = 'family@careconnect.com'), 'David', 'Johnson', 'family@careconnect.com', '555-0123');

-- ============================================
-- 5. CAREGIVER_PATIENT_LINK - Use created_by not granted_by
-- ============================================

UPDATE caregiver_patient_link
SET status = 'ACTIVE'
WHERE status IS NULL;

UPDATE caregiver_patient_link
SET link_type = 'PERMANENT'
WHERE link_type IS NULL;

INSERT INTO caregiver_patient_link (caregiver_user_id, patient_user_id, created_by, status, link_type, created_at)
SELECT
	(SELECT id FROM users WHERE email = 'caregiver@careconnect.com'),
	(SELECT id FROM users WHERE email = 'patient@careconnect.com'),
	(SELECT id FROM users WHERE email = 'patient@careconnect.com'),
	'ACTIVE',
	'PERMANENT',
	'2024-06-15 10:30:00'
WHERE NOT EXISTS (
	SELECT 1 FROM caregiver_patient_link
	WHERE caregiver_user_id = (SELECT id FROM users WHERE email = 'caregiver@careconnect.com')
	  AND patient_user_id = (SELECT id FROM users WHERE email = 'patient@careconnect.com')
	  AND status = 'ACTIVE'
);

INSERT INTO caregiver_patient_link (caregiver_user_id, patient_user_id, created_by, status, link_type, created_at)
SELECT
    (SELECT id FROM users WHERE email = 'sarah.mitchell@careconnect.com'),
    (SELECT id FROM users WHERE email = 'patient@careconnect.com'),
    (SELECT id FROM users WHERE email = 'sarah.mitchell@careconnect.com'),
    'ACTIVE',
    'PERMANENT',
    '2024-06-15 10:35:00'
WHERE NOT EXISTS (
    SELECT 1 FROM caregiver_patient_link
    WHERE caregiver_user_id = (SELECT id FROM users WHERE email = 'sarah.mitchell@careconnect.com')
      AND patient_user_id = (SELECT id FROM users WHERE email = 'patient@careconnect.com')
      AND status = 'ACTIVE'
);

INSERT INTO providers (name, specialty, organization, phone, email)
SELECT
    'Dr. Sarah Mitchel, MD',
    'Internal Medicine',
    'CareConnect Medical Group',
    '(555) 123-4567',
    'sarah.mitchell@careconnect.com'
WHERE NOT EXISTS (
    SELECT 1 FROM providers WHERE email = 'sarah.mitchell@careconnect.com'
);

UPDATE providers
SET name = 'Dr. Sarah Mitchel, MD',
    specialty = 'Internal Medicine',
    organization = 'CareConnect Medical Group',
    phone = '(555) 123-4567'
WHERE email = 'sarah.mitchell@careconnect.com';

UPDATE patient
SET primary_care_provider_id = (
    SELECT p.id FROM providers p WHERE p.email = 'sarah.mitchell@careconnect.com' LIMIT 1
)
WHERE user_id = (SELECT id FROM users WHERE email = 'patient@careconnect.com')
  AND (primary_care_provider_id IS NULL OR primary_care_provider_id <> (
      SELECT p.id FROM providers p WHERE p.email = 'sarah.mitchell@careconnect.com' LIMIT 1
  ));

-- ============================================
-- 6. FAMILY_MEMBER_LINK
-- ============================================

INSERT INTO family_member_link (family_user_id, patient_user_id, granted_by, status, created_at)
SELECT
	(SELECT id FROM users WHERE email = 'family@careconnect.com'),
	(SELECT id FROM users WHERE email = 'patient@careconnect.com'),
	(SELECT id FROM users WHERE email = 'patient@careconnect.com'),
	'ACTIVE',
	'2024-07-10 16:30:00'
WHERE NOT EXISTS (
	SELECT 1 FROM family_member_link
	WHERE family_user_id = (SELECT id FROM users WHERE email = 'family@careconnect.com')
	  AND patient_user_id = (SELECT id FROM users WHERE email = 'patient@careconnect.com')
	  AND status = 'ACTIVE'
);

-- ============================================
-- 7. PATIENT_MEDICATION - Remove updated_at column
-- ============================================

INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at) VALUES
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Metformin', '500mg', 'Twice daily', 'Oral', 'PRESCRIPTION', 'Dr. Sarah Mitchel', '2024-06-20', '2024-06-20', NULL, 'Take with meals to reduce stomach upset', true, 'PENDING', '2024-06-20 10:00:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Lisinopril', '10mg', 'Once daily', 'Oral', 'PRESCRIPTION', 'Dr. Sarah Mitchel', '2024-06-20', '2024-06-20', NULL, 'For blood pressure control', true, 'PENDING', '2024-06-20 10:00:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Atorvastatin', '20mg', 'Once daily at bedtime', 'Oral', 'PRESCRIPTION', 'Dr. Sarah Mitchel', '2024-07-15', '2024-07-15', NULL, 'For cholesterol management', true, 'PENDING', '2024-07-15 14:00:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Aspirin', '81mg', 'Once daily', 'Oral', 'SUPPLEMENT', 'Dr. Sarah Mitchel', '2024-06-20', '2024-06-20', NULL, 'Low-dose for cardiovascular protection', true, 'PENDING', '2024-06-20 10:00:00');

-- ============================================
-- 8. PATIENT_ALLERGY - Remove updated_at column
-- ============================================

INSERT INTO patient_allergy (patient_id, allergen, allergy_type, severity, reaction, notes, diagnosed_date, is_active, created_at) VALUES
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Penicillin', 'MEDICATION', 'MODERATE', 'Rash and itching', 'Developed reaction in 2010. Use alternative antibiotics.', '2010-03-15', true, '2024-06-15 10:30:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Shellfish', 'FOOD', 'SEVERE', 'Anaphylaxis, difficulty breathing', 'Carries EpiPen. Avoid all shellfish.', '1998-07-20', true, '2024-06-15 10:30:00');

-- ============================================
-- 9. MOOD_PAIN_LOG - Remove updated_at column
-- ============================================

INSERT INTO mood_pain_log (patient_id, mood_value, pain_value, note, timestamp, created_at) VALUES
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 8, 3, 'Feeling good today. Slight knee discomfort.', '2025-10-06 08:30:00', '2025-10-06 08:30:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 7, 4, 'Knees bothering me more than usual.', '2025-10-05 08:30:00', '2025-10-05 08:30:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 8, 2, 'Slept well. Minimal pain.', '2025-10-04 08:30:00', '2025-10-04 08:30:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 9, 2, 'Great day! Took a nice walk.', '2025-10-03 08:30:00', '2025-10-03 08:30:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 7, 3, 'Feeling okay. Normal day.', '2025-10-02 08:30:00', '2025-10-02 08:30:00');

-- ============================================
-- 10. SYMPTOM_ENTRY - Remove updated_at column
-- ============================================

INSERT INTO symptom_entry (patient_id, caregiver_id, symptom_key, symptom_value, severity, notes, taken_at, completed, created_at, updated_at) VALUES
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver@careconnect.com'), 'FATIGUE', 'Mild tiredness', 2, NULL, '2025-10-05 14:00:00', true, '2025-10-05 14:00:00', '2025-10-05 14:00:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver@careconnect.com'), 'JOINT_PAIN', 'Knee stiffness', 3, NULL, '2025-10-05 08:30:00', true, '2025-10-05 08:30:00', '2025-10-05 08:30:00'),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver@careconnect.com'), 'DIZZINESS', 'Brief lightheadedness when standing', 1, NULL, '2025-10-03 16:00:00', true, '2025-10-03 16:00:00', '2025-10-03 16:00:00');

-- ============================================
-- 11. WEARABLE_METRIC - Fixed MetricType enum values, remove updated_at
-- ============================================

INSERT INTO wearable_metric (patient_user_id, metric, metric_value, recorded_at, created_at) VALUES
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'HEART_RATE', 74, '2025-10-06 12:00:00', '2025-10-06 12:00:00'),
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'HEART_RATE', 76, '2025-10-05 12:00:00', '2025-10-05 12:00:00'),
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'HEART_RATE', 72, '2025-10-04 12:00:00', '2025-10-04 12:00:00'),
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'SPO2', 97, '2025-10-06 12:00:00', '2025-10-06 12:00:00'),
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'SPO2', 98, '2025-10-05 12:00:00', '2025-10-05 12:00:00'),
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'SPO2', 97, '2025-10-04 12:00:00', '2025-10-04 12:00:00');

-- ============================================
-- 12. TASKS - Use isCompleted (boolean) not iscompleted, remove updated_at
-- ============================================

INSERT INTO tasks (patient_id, name, description, date, time_of_day, is_completed, task_type, days_of_week) VALUES
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Take Morning Medications', 'Metformin, Lisinopril, Aspirin', '2025-10-06', '08:00:00', true, 'MEDICATION', '[]'::jsonb),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Check Blood Sugar', 'Fasting blood glucose reading', '2025-10-06', '07:30:00', true, 'HEALTH_CHECK', '[]'::jsonb),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Take Evening Medications', 'Metformin, Atorvastatin', '2025-10-06', '19:00:00', false, 'MEDICATION', '[]'::jsonb),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Daily Walk', '15-minute walk around the block', '2025-10-06', '14:00:00', false, 'EXERCISE', '["MONDAY","WEDNESDAY","FRIDAY"]'::jsonb),
((SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com'), 'Drink Water', '8 glasses throughout the day', '2025-10-06', '10:00:00', false, 'WELLNESS', '["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]'::jsonb);

-- ============================================
-- 13. VITAL_SAMPLE - Table doesn't exist, removing these entries
-- ============================================

-- Note: vital_sample table not found in current schema, skipping vitals data

-- ============================================
-- 14. PLAN - Ensure development plans exist
-- ============================================

INSERT INTO plan (code, name, price_cents, billing_period, is_active)
SELECT 'STANDARD', 'Standard Plan', 2000, 'MONTH', TRUE
WHERE NOT EXISTS (SELECT 1 FROM plan WHERE code = 'STANDARD');

INSERT INTO plan (code, name, price_cents, billing_period, is_active)
SELECT 'PREMIUM', 'Premium Plan', 3000, 'MONTH', TRUE
WHERE NOT EXISTS (SELECT 1 FROM plan WHERE code = 'PREMIUM');

-- ============================================
-- 15. SUBSCRIPTIONS - Match current schema (`subscriptions`)
-- ============================================

INSERT INTO subscriptions (user_id, plan_id, status, started_at, current_period_end, payment_subscription_id, payment_customer_id, price_id)
SELECT
	(SELECT id FROM users WHERE email = 'patient@careconnect.com'),
	(SELECT id FROM plan WHERE code = 'PREMIUM' LIMIT 1),
	'ACTIVE',
	'2024-06-15 10:00:00',
	'2025-11-15 10:00:00',
	'sub_mock_patient_001',
	'cus_mock_patient_001',
	'price_mock_premium'
WHERE NOT EXISTS (
	SELECT 1 FROM subscriptions WHERE payment_subscription_id = 'sub_mock_patient_001'
);

-- ============================================
-- 16. SECOND PATIENT/CAREGIVER PAIR — a genuinely independent second patient and
-- second caregiver, linked only to each other. With a single patient in the seed
-- data, code that accidentally conflates patient.id with users.id (or scopes a
-- caregiver query by the wrong one) can still return correct-looking results,
-- since every lookup resolves to the same lone patient regardless of which id it
-- used. This pair exists to catch that class of bug: caregiver2@careconnect.com
-- must see I.M. Sickly's records and must NOT see Mary Johnson's, and vice versa
-- for caregiver@careconnect.com / sarah.mitchell@careconnect.com against I.M. Sickly.
-- ============================================

INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at)
SELECT 'patient2@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'PATIENT', 'ACTIVE', '2024-08-20', '2024-08-19 09:00:00'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'patient2@careconnect.com');

INSERT INTO users (email, email_verified, password, password_hash, role, status, last_login_date, created_at)
SELECT 'caregiver2@careconnect.com', true, 'password', '$2a$10$a5mrP5BJfagHEYTGsrgPGOYcC0X80L4RUSf2BcHlcccS.IdJgoANq', 'CAREGIVER', 'ACTIVE', '2024-08-20', '2024-08-19 09:00:00'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'caregiver2@careconnect.com');

INSERT INTO patient (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender)
SELECT
    (SELECT id FROM users WHERE email = 'patient2@careconnect.com'),
    'I.M.', 'Sickly', '1971-11-02', 'patient2@careconnect.com', '555-0102',
    '87 Birchwood Lane', NULL, 'Falls Chrurch', 'VA', '22046', 'MALE'
WHERE NOT EXISTS (
    SELECT 1 FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'
);

INSERT INTO caregiver (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender, caregiver_type)
SELECT
    (SELECT id FROM users WHERE email = 'caregiver2@careconnect.com'),
    'Cara', 'Giver', '1990-02-17', 'caregiver2@careconnect.com', '555-0201',
    '321 Healthcare Plaza', 'Suite 210', 'Falls Chrurch', 'VA', '22046', 'MALE', 'RN'
WHERE NOT EXISTS (
    SELECT 1 FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver2@careconnect.com'
);

INSERT INTO caregiver_patient_link (caregiver_user_id, patient_user_id, created_by, status, link_type, created_at)
SELECT
	(SELECT id FROM users WHERE email = 'caregiver2@careconnect.com'),
	(SELECT id FROM users WHERE email = 'patient2@careconnect.com'),
	(SELECT id FROM users WHERE email = 'patient2@careconnect.com'),
	'ACTIVE',
	'PERMANENT',
	'2024-08-19 09:30:00'
WHERE NOT EXISTS (
	SELECT 1 FROM caregiver_patient_link
	WHERE caregiver_user_id = (SELECT id FROM users WHERE email = 'caregiver2@careconnect.com')
	  AND patient_user_id = (SELECT id FROM users WHERE email = 'patient2@careconnect.com')
	  AND status = 'ACTIVE'
);

-- Medications: Lisinopril is deliberately also prescribed to patient@careconnect.com
-- (different dosage) — a same-drug-name-different-patient case that would leak or
-- get conflated if any query joined on medication_name instead of patient_id. The
-- remaining rows span every Medication.MedicationType value (PRESCRIPTION,
-- OVER_THE_COUNTER, SUPPLEMENT, HERBAL, EMERGENCY) plus a discontinued/inactive
-- medication with an end_date, since active-only filtering is easy to get backwards.
INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Lisinopril', '20mg', 'Once daily', 'Oral', 'PRESCRIPTION', 'Cara Giver', '2024-08-20', '2024-08-20', NULL, 'For blood pressure control', true, 'PENDING', '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_medication pm JOIN patient p ON pm.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pm.medication_name = 'Lisinopril'
);

INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Warfarin', '5mg', 'Once daily', 'Oral', 'PRESCRIPTION', 'Cara Giver', '2024-08-20', '2024-08-20', NULL, 'Anticoagulant, requires regular INR checks', true, 'APPROVED', '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_medication pm JOIN patient p ON pm.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pm.medication_name = 'Warfarin'
);

INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Fish Oil', '1000mg', 'Once daily', 'Oral', 'SUPPLEMENT', 'Cara Giver', '2024-08-20', '2024-08-20', NULL, 'For cardiovascular support', true, 'APPROVED', '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_medication pm JOIN patient p ON pm.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pm.medication_name = 'Fish Oil'
);

INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'St. John''s Wort', '300mg', 'Three times daily', 'Oral', 'HERBAL', 'Cara Giver', '2024-08-20', '2024-08-20', NULL, 'Self-reported by patient, not yet reviewed', true, 'PENDING', '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_medication pm JOIN patient p ON pm.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pm.medication_name = 'St. John''s Wort'
);

INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Epinephrine (EpiPen)', '0.3mg', 'As needed', 'Intramuscular', 'EMERGENCY', 'Cara Giver', '2024-08-20', '2024-08-20', NULL, 'For severe allergic reaction, see peanut allergy', true, 'APPROVED', '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_medication pm JOIN patient p ON pm.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pm.medication_name = 'Epinephrine (EpiPen)'
);

INSERT INTO patient_medication (patient_id, medication_name, dosage, frequency, route, medication_type, prescribed_by, prescribed_date, start_date, end_date, notes, is_active, approval_status, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Ibuprofen', '200mg', 'As needed', 'Oral', 'OVER_THE_COUNTER', 'Cara Giver', '2024-08-20', '2024-08-20', '2025-09-01', 'Discontinued due to interaction with Warfarin', false, 'REMOVAL_PENDING', '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_medication pm JOIN patient p ON pm.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pm.medication_name = 'Ibuprofen'
);

-- ============================================
-- RETRIEVAL INDEXING — a raw INSERT into patient_medication is invisible to Ask AI.
-- Retrieval only ever searches retrieval_index_chunk, which is normally populated
-- either by the async outbox pipeline (real API writes: call summaries, clinical
-- notes, etc.) or by RetrievalIndexingService's synchronous admin/dev backfill
-- (POST /v1/api/ai/index/{patientId}). Neither one fires for a plain SQL INSERT,
-- so without this section every medication seeded above is unretrievable and every
-- Ask AI question about it returns NO_RECORDS after a clean redeploy.
--
-- This mirrors RetrievalIndexingService.indexMedications()/buildMedicationText()
-- exactly (same chunk_text format, same record_type/source_record_id shape) for
-- every ACTIVE medication belonging to any patient inserted above — not hardcoded
-- to a specific patient, so it covers new patients added to this file later too.
-- embedding is intentionally left NULL: retrieval_index_chunk has a dedicated
-- backfill index for exactly that case, and ChunkEmbeddingBackfillWorker (polls
-- every 60s) fills it in automatically once Bedrock is reachable. search_vector
-- is populated by the trg_retrieval_index_chunk_search_vector DB trigger, not here.
-- ============================================

DELETE FROM retrieval_index_chunk
WHERE record_type = 'MEDICATION'
  AND source_record_id IN (SELECT 'medication-' || id FROM patient_medication WHERE is_active = true);

INSERT INTO retrieval_index_chunk (patient_id, record_type, source_record_id, chunk_text, migration_status, indexed_at)
SELECT
    pm.patient_id,
    'MEDICATION',
    'medication-' || pm.id,
    'Medication: ' || pm.medication_name
        || CASE WHEN pm.dosage IS NOT NULL THEN ', Dosage: ' || pm.dosage ELSE '' END
        || CASE WHEN pm.frequency IS NOT NULL THEN ', Frequency: ' || pm.frequency ELSE '' END
        || CASE WHEN pm.route IS NOT NULL THEN ', Route: ' || pm.route ELSE '' END
        || CASE WHEN pm.prescribed_by IS NOT NULL THEN ', Prescribed by: ' || pm.prescribed_by ELSE '' END
        || CASE WHEN pm.start_date IS NOT NULL THEN ', Start date: ' || pm.start_date ELSE '' END
        || CASE WHEN pm.end_date IS NOT NULL THEN ', End date: ' || pm.end_date ELSE '' END
        || CASE WHEN pm.notes IS NOT NULL THEN '. Notes: ' || pm.notes ELSE '' END
        || '. Status: ' || CASE WHEN pm.is_active THEN 'Active' ELSE 'Inactive' END,
    'ACTIVE',
    now()
FROM patient_medication pm
WHERE pm.is_active = true;

-- Symptom entries: boundary severity values (1 = min, 5 = max per the documented
-- 1-5 range) plus one with severity intentionally NULL, since the column is
-- nullable but nothing in the schema enforces it ever being populated.
INSERT INTO symptom_entry (patient_id, caregiver_id, symptom_key, symptom_value, severity, notes, taken_at, completed, created_at, updated_at)
SELECT
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver2@careconnect.com'),
    'HEADACHE', 'Slight tension headache', 1, NULL, '2025-10-05 09:00:00', true, '2025-10-05 09:00:00', '2025-10-05 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM symptom_entry se JOIN patient p ON se.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND se.symptom_key = 'HEADACHE'
);

INSERT INTO symptom_entry (patient_id, caregiver_id, symptom_key, symptom_value, severity, notes, taken_at, completed, created_at, updated_at)
SELECT
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver2@careconnect.com'),
    'JOINT_PAIN', 'Persistent stiffness in both knees', 5, 'Worse after long walks, discussed with caregiver.', '2025-10-04 18:00:00', true, '2025-10-04 18:00:00', '2025-10-04 18:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM symptom_entry se JOIN patient p ON se.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND se.symptom_key = 'JOINT_PAIN'
);

INSERT INTO symptom_entry (patient_id, caregiver_id, symptom_key, symptom_value, severity, notes, taken_at, completed, created_at, updated_at)
SELECT
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver2@careconnect.com'),
    'FATIGUE', 'General tiredness reported', NULL, 'Patient did not provide a numeric severity rating.', '2025-10-03 18:00:00', true, '2025-10-03 18:00:00', '2025-10-03 18:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM symptom_entry se JOIN patient p ON se.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND se.symptom_key = 'FATIGUE'
);

-- Mood/pain log: boundary extremes of the enforced 1-10 mood / 0-10 pain range.
INSERT INTO mood_pain_log (patient_id, mood_value, pain_value, note, timestamp, created_at)
SELECT
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    1, 10, 'Very difficult day, significant pain throughout.', '2025-10-05 08:00:00', '2025-10-05 08:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM mood_pain_log mpl JOIN patient p ON mpl.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND mpl.timestamp = '2025-10-05 08:00:00'
);

INSERT INTO mood_pain_log (patient_id, mood_value, pain_value, note, timestamp, created_at)
SELECT
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    10, 0, 'Excellent day, no pain at all.', '2025-10-04 08:00:00', '2025-10-04 08:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM mood_pain_log mpl JOIN patient p ON mpl.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND mpl.timestamp = '2025-10-04 08:00:00'
);

-- Allergies: patient1 has allergy data but patient1 was the only one exercising
-- this table — the peanut allergy pairs with the EpiPen medication above so
-- retrieval/grounding tests have a realistic cross-table linkage to verify.
INSERT INTO patient_allergy (patient_id, allergen, allergy_type, severity, reaction, notes, diagnosed_date, is_active, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Sulfa drugs', 'MEDICATION', 'MODERATE', 'Hives and swelling', 'Avoid sulfonamide antibiotics.', '2015-02-10', true, '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_allergy pa JOIN patient p ON pa.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pa.allergen = 'Sulfa drugs'
);

INSERT INTO patient_allergy (patient_id, allergen, allergy_type, severity, reaction, notes, diagnosed_date, is_active, created_at)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Peanuts', 'FOOD', 'SEVERE', 'Anaphylaxis risk', 'Carries EpiPen at all times.', '1995-06-01', true, '2024-08-20 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM patient_allergy pa JOIN patient p ON pa.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND pa.allergen = 'Peanuts'
);

-- ============================================
-- 18. TASKS, SCHEDULED VISIT, AND CLINICAL OBSERVATIONS FOR I.M. SICKLY
-- Broadens Ask AI demo coverage beyond medications to appointments and
-- side-effect/symptom questions. tasks and scheduled_visits have no automatic
-- indexing path (same gap medications had before section 17 above), so this
-- inserts real source rows plus retrieval_index_chunk rows directly.
--   TASK -> RetrievalIndexingService.buildTaskText() shape.
-- The appointment and symptom-summary chunks are recorded as CLINICAL_NOTE, not
-- SUMMARY_APPOINTMENT/SUMMARY_CLINICAL_OBSERVATION: those SUMMARY_* record types
-- are subject to a background summary-citation-replay lifecycle that validates
-- them against a real call/visit summary source and QUARANTINEs anything it
-- can't verify (confirmed empirically — chunks inserted with those types and a
-- fabricated source_record_id get flipped from ACTIVE to QUARANTINED within
-- about a minute, silently dropping them from retrieval). CLINICAL_NOTE has no
-- such lifecycle, so it's the safe choice for hand-seeded demo chunks.
-- ============================================

INSERT INTO tasks (patient_id, name, description, date, time_of_day, is_completed, task_type, days_of_week, frequency)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Take Blood Pressure Medication', 'Lisinopril 20mg', '2026-08-28', '08:00:00', true, 'MEDICATION', '[]'::jsonb, 'Daily'
WHERE NOT EXISTS (
    SELECT 1 FROM tasks t JOIN patient p ON t.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND t.name = 'Take Blood Pressure Medication'
);

INSERT INTO tasks (patient_id, name, description, date, time_of_day, is_completed, task_type, days_of_week, frequency)
SELECT (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'), 'Check Blood Pressure', 'Home blood pressure reading', '2026-08-28', '08:30:00', false, 'HEALTH_CHECK', '[]'::jsonb, 'Daily'
WHERE NOT EXISTS (
    SELECT 1 FROM tasks t JOIN patient p ON t.patient_id = p.id JOIN users u ON p.user_id = u.id
    WHERE u.email = 'patient2@careconnect.com' AND t.name = 'Check Blood Pressure'
);

-- TASK indexing — generic across all patients, mirrors buildTaskText() exactly.
DELETE FROM retrieval_index_chunk
WHERE record_type = 'TASK'
  AND source_record_id IN (SELECT 'task-' || id FROM tasks);

INSERT INTO retrieval_index_chunk (patient_id, record_type, source_record_id, chunk_text, migration_status, indexed_at)
SELECT
    t.patient_id,
    'TASK',
    'task-' || t.id,
    'Task: ' || t.name
        || CASE WHEN t.task_type IS NOT NULL THEN ', Type: ' || t.task_type ELSE '' END
        || CASE WHEN t.description IS NOT NULL THEN ', Description: ' || t.description ELSE '' END
        || CASE WHEN t.date IS NOT NULL THEN ', Date: ' || t.date ELSE '' END
        || CASE WHEN t.time_of_day IS NOT NULL THEN ', Time: ' || t.time_of_day ELSE '' END
        || CASE WHEN t.frequency IS NOT NULL THEN ', Frequency: ' || t.frequency ELSE '' END
        || ', Completed: ' || CASE WHEN t.is_completed THEN 'Yes' ELSE 'No' END,
    'ACTIVE',
    now()
FROM tasks t;

-- Scheduled visit for "does the patient have any appointments scheduled".
-- caregiver_id/patient_id follow this schema's established convention (the
-- entity table's own PK, confirmed for patient_id via
-- ScheduledVisitController's patientRepository.findById(patientId) lookup).
INSERT INTO scheduled_visits (caregiver_id, patient_id, service_type, scheduled_date, scheduled_time, duration_minutes, priority, notes, status, created_at, updated_at)
SELECT
    (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver2@careconnect.com'),
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    'Cardiology Follow-up Visit', '2026-09-15', '10:30:00', 60, 'Normal',
    'Reviewing blood pressure medication and heart rate', 'Scheduled', now(), now()
WHERE NOT EXISTS (
    SELECT 1 FROM scheduled_visits
    WHERE patient_id = (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com')
      AND service_type = 'Cardiology Follow-up Visit'
);

DELETE FROM retrieval_index_chunk
WHERE patient_id = (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com')
  AND record_type = 'CLINICAL_NOTE' AND source_record_id LIKE 'scheduled-visit-%';

INSERT INTO retrieval_index_chunk (patient_id, record_type, source_record_id, chunk_text, migration_status, indexed_at)
SELECT
    sv.patient_id,
    'CLINICAL_NOTE',
    'scheduled-visit-' || sv.id,
    'The patient has an appointment scheduled: a ' || sv.service_type || ' with caregiver Cara Giver on '
        || sv.scheduled_date || ' at ' || sv.scheduled_time || '. ' || sv.notes || '.',
    'ACTIVE',
    now()
FROM scheduled_visits sv
WHERE sv.patient_id = (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com')
  AND sv.service_type = 'Cardiology Follow-up Visit';

-- Clinical-observation summary derived from the seeded symptom entries, for
-- "is the patient experiencing side effects" — phrased like a real extracted
-- SUMMARY_CLINICAL_OBSERVATION chunk (SummaryChunker.buildClinicalObservationsText:
-- labeled sections, semicolon-joined items), with an explicit medication-related
-- side-effect line since none of the raw symptom_entry rows are framed that way.
DELETE FROM retrieval_index_chunk
WHERE patient_id = (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com')
  AND record_type = 'CLINICAL_NOTE' AND source_record_id = 'symptom-summary-1';

INSERT INTO retrieval_index_chunk (patient_id, record_type, source_record_id, chunk_text, migration_status, indexed_at)
SELECT
    (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient2@careconnect.com'),
    'CLINICAL_NOTE',
    'symptom-summary-1',
    'The patient is experiencing the following symptoms and possible side effects: '
        || string_agg(se.symptom_value, '; ' ORDER BY se.taken_at DESC) || '. '
        || 'The patient is experiencing mild fatigue, which may be a side effect related to the recently started Warfarin therapy.',
    'ACTIVE',
    now()
FROM symptom_entry se
JOIN patient p ON se.patient_id = p.id
JOIN users u ON p.user_id = u.id
WHERE u.email = 'patient2@careconnect.com'
GROUP BY p.id;
