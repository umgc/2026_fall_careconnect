-- V21__update_pain_scale_to_0_10.sql
-- Update pain value scale from 1-10 to 0-10 to support "No pain" (0 value)


-- Add new check constraint allowing pain_value from 0 to 10
ALTER TABLE mood_pain_log ADD CONSTRAINT chk_pain_value_0_10 CHECK (pain_value >= 0 AND pain_value <= 10);

-- Keep mood_value constraint as 1-10 (no change needed for mood)
-- The mood_value constraint should remain: CHECK (mood_value >= 1 AND mood_value <= 10)
