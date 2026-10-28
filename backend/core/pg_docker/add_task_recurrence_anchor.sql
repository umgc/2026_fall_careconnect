-- Needed only for environments where Hibernate schema updates are disabled.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence_anchor_date VARCHAR(255);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence_excluded_dates TEXT;
