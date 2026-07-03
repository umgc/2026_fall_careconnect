-- Create Roles Table mapping to User `@ElementCollection` (WBS 2.5.1)
CREATE TABLE user_roles (
    user_id BIGINT NOT NULL,
    role_name VARCHAR(50) NOT NULL,
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_user_role UNIQUE (user_id, role_name)
);

-- Index for faster authority checks during authentication cycles
CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);

-- Create Care Circle Link Table to bind Caregivers to Patients (WBS 2.5.1)
CREATE TABLE care_circle_links (
    id BIGSERIAL PRIMARY KEY,
    caregiver_id BIGINT NOT NULL,
    patient_id BIGINT NOT NULL,
    relationship_type VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_care_circle_pair UNIQUE (caregiver_id, patient_id)
);

-- Migrate existing data from old schema column to relation table
INSERT INTO user_roles (user_id, role_name)
SELECT id, role FROM users 
WHERE role IS NOT NULL;