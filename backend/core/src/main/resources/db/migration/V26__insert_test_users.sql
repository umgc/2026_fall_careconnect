-- Insert test users for local development
-- Password for both users is "1234"
-- BCrypt hash for "1234": $2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi.

INSERT INTO users (
    name,
    email,
    password,
    password_hash,
    role,
    email_verified,
    verification_token,
    stripe_customer_id,
    created_at,
    last_login,
    profile_image_url,
    status,
    last_login_date,
    login_streak,
    leaderboard_opt_in
) VALUES
(
    'Test Caregiver',
    'test@caregiver',
    '1234',
    '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi.',
    'CAREGIVER',
    TRUE,
    NULL,
    NULL,
    CURRENT_TIMESTAMP,
    NULL,
    NULL,
    'ACTIVE',
    NULL,
    0,
    TRUE
),
(
    'Test Patient',
    'test@patient',
    '1234',
    '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi.',
    'PATIENT',
    TRUE,
    NULL,
    NULL,
    CURRENT_TIMESTAMP,
    NULL,
    NULL,
    'ACTIVE',
    NULL,
    0,
    TRUE
);