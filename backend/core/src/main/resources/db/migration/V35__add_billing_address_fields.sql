-- Add billing address fields to users table for address autocomplete + tax calculation

ALTER TABLE users ADD COLUMN IF NOT EXISTS address_line1 VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_line2 VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS city VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS state CHAR(2);
ALTER TABLE users ADD COLUMN IF NOT EXISTS postal_code VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS country CHAR(2) DEFAULT 'US';
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_place_id VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_formatted TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_latitude NUMERIC(10, 8);
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_longitude NUMERIC(11, 8);

-- Create index on state for tax queries
CREATE INDEX IF NOT EXISTS idx_users_state ON users(state);
