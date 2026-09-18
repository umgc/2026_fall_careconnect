-- ============================================
-- CareConnect Mock Data Generation - Fixed Schema
-- 1 Patient, 1 Caregiver, 1 Family Member
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

-- ============================================
-- 2. PATIENT TABLE - Use embedded Address fields (line1, line2, not address_line1/2)
-- ============================================

INSERT INTO patient (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender) VALUES
((SELECT id FROM users WHERE email = 'patient@careconnect.com'), 'Mary', 'Johnson', '1958-03-15', 'patient@careconnect.com', '555-0101', '123 Maple Street', 'Apt 4B', 'Springfield', 'IL', '62701', 'FEMALE');

-- ============================================
-- 3. CAREGIVER TABLE - Use embedded Address fields (line1, line2, not address_line1/2)
-- ============================================

INSERT INTO caregiver (user_id, first_name, last_name, dob, email, phone, line1, line2, city, state, zip, gender, caregiver_type) VALUES
((SELECT id FROM users WHERE email = 'caregiver@careconnect.com'), 'Jennifer', 'Smith', '1985-09-12', 'caregiver@careconnect.com', '555-0200', '321 Healthcare Plaza', 'Suite 200', 'Chicago', 'IL', '60607', 'FEMALE', 'RN');

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
    'Chicago',
    'IL',
    '60616',
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
