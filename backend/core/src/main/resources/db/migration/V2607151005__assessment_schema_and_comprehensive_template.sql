/* ---- TICKET #83: DIGITAL ASSESSMENT SCHEMA ---- */

ALTER TABLE questions
  ADD COLUMN IF NOT EXISTS form_key VARCHAR(64) NOT NULL DEFAULT 'virtual-checkin',
  ADD COLUMN IF NOT EXISTS form_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS section_key VARCHAR(64) NOT NULL DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS field_key VARCHAR(128),
  ADD COLUMN IF NOT EXISTS score_weight NUMERIC(8,2);

UPDATE questions
SET field_key = LOWER(
  REGEXP_REPLACE(
    REGEXP_REPLACE(prompt, '[^a-zA-Z0-9]+', '_', 'g'),
    '^_+|_+$',
    '',
    'g'
  )
)
WHERE field_key IS NULL OR field_key = '';

UPDATE questions
SET field_key = CONCAT('question_', id)
WHERE field_key IS NULL OR field_key = '';

ALTER TABLE questions
  ALTER COLUMN field_key SET NOT NULL;

ALTER TABLE check_in_questions
  ADD COLUMN IF NOT EXISTS form_key_snapshot VARCHAR(64) NOT NULL DEFAULT 'virtual-checkin',
  ADD COLUMN IF NOT EXISTS form_version_snapshot INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS section_key_snapshot VARCHAR(64) NOT NULL DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS field_key_snapshot VARCHAR(128) NOT NULL DEFAULT 'question',
  ADD COLUMN IF NOT EXISTS score_weight_snapshot NUMERIC(8,2);

UPDATE check_in_questions ciq
SET form_key_snapshot = q.form_key,
    form_version_snapshot = q.form_version,
    section_key_snapshot = q.section_key,
    field_key_snapshot = q.field_key,
    score_weight_snapshot = q.score_weight
FROM questions q
WHERE q.id = ciq.question_id;

/* Sample comprehensive assessment template (v1) */
INSERT INTO questions (prompt, type, required, ordinal, active, form_key, form_version, section_key, field_key, score_weight)
SELECT * FROM (
  VALUES
    ('Did you take all prescribed medications in the last 24 hours?', 'YES_NO', TRUE, 1, TRUE, 'comprehensive-assessment', 1, 'medication_adherence', 'medication_taken_last_24h', 2.00),
    ('How many medication doses were missed today?', 'NUMBER', TRUE, 2, TRUE, 'comprehensive-assessment', 1, 'medication_adherence', 'missed_doses_today', 2.00),
    ('List any medication side effects you noticed.', 'TEXT', FALSE, 3, TRUE, 'comprehensive-assessment', 1, 'medication_adherence', 'medication_side_effects', 1.50),
    ('Rate your pain level right now (0-10).', 'NUMBER', TRUE, 10, TRUE, 'comprehensive-assessment', 1, 'symptom_tracking', 'pain_level_now', 2.00),
    ('Have you experienced dizziness, shortness of breath, or chest discomfort today?', 'YES_NO', TRUE, 11, TRUE, 'comprehensive-assessment', 1, 'symptom_tracking', 'critical_symptoms_today', 3.00),
    ('Describe any new or worsening symptoms.', 'TEXT', FALSE, 12, TRUE, 'comprehensive-assessment', 1, 'symptom_tracking', 'new_worsening_symptoms', 2.00),
    ('How would you rate your mood today (0-10)?', 'NUMBER', TRUE, 20, TRUE, 'comprehensive-assessment', 1, 'mental_wellness', 'mood_today', 1.50),
    ('I felt overwhelmed or anxious today.', 'TRUE_FALSE', FALSE, 21, TRUE, 'comprehensive-assessment', 1, 'mental_wellness', 'felt_overwhelmed_today', 1.50),
    ('Share anything affecting your emotional well-being today.', 'TEXT', FALSE, 22, TRUE, 'comprehensive-assessment', 1, 'mental_wellness', 'emotional_notes', 1.00),
    ('Did you complete at least one meaningful activity today?', 'YES_NO', FALSE, 30, TRUE, 'comprehensive-assessment', 1, 'daily_function', 'completed_meaningful_activity', 1.00),
    ('Do you currently feel safe at home?', 'YES_NO', TRUE, 31, TRUE, 'comprehensive-assessment', 1, 'daily_function', 'feels_safe_at_home', 3.00),
    ('What support do you need from your care team before the next check-in?', 'TEXT', FALSE, 32, TRUE, 'comprehensive-assessment', 1, 'daily_function', 'requested_support', 1.00)
) AS seed(prompt, type, required, ordinal, active, form_key, form_version, section_key, field_key, score_weight)
WHERE NOT EXISTS (
  SELECT 1
  FROM questions q
  WHERE q.form_key = seed.form_key
    AND q.form_version = seed.form_version
    AND q.field_key = seed.field_key
);
