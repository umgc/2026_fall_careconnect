-- Add login tracking fields to users table

ALTER TABLE users
ADD COLUMN last_login_date DATE,
ADD COLUMN login_streak INTEGER NOT NULL DEFAULT 0,
ADD COLUMN leaderboard_opt_in BOOLEAN NOT NULL DEFAULT TRUE;