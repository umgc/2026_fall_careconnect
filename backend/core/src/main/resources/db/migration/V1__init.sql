-- 1. RBAC core

CREATE TABLE users
(
    id             BIGSERIAL PRIMARY KEY,
    email          VARCHAR(254) NOT NULL UNIQUE,
    email_verified BOOLEAN     DEFAULT FALSE,
    password       VARCHAR(255) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    role           VARCHAR(20)  NOT NULL
        CHECK (role IN ('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER', 'ADMIN')),
    status         VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED')),
    created_at     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE caregiver
(
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT       NOT NULL UNIQUE,
    first_name       VARCHAR(100),
    last_name        VARCHAR(100),
    dob              DATE,
    email            VARCHAR(254) NOT NULL UNIQUE,
    phone            VARCHAR(32),
    address_line1    VARCHAR(255),
    address_line2    VARCHAR(255),
    city             VARCHAR(100),
    state            VARCHAR(50),
    zip              VARCHAR(20),
    caregiver_type   VARCHAR(20)  NOT NULL,
    license_number   VARCHAR(100),
    issuing_state    VARCHAR(10),
    years_experience INT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- 2. Profiles
CREATE TABLE patient
(
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT       NOT NULL UNIQUE,
    first_name    VARCHAR(100),
    last_name     VARCHAR(100),
    dob           DATE,
    email         VARCHAR(254) NOT NULL UNIQUE,
    phone         VARCHAR(32),
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city          VARCHAR(100),
    state         VARCHAR(50),
    zip           VARCHAR(20),
    sex           VARCHAR(10) CHECK (sex IN ('M', 'F', 'OTHER')),
    medical_notes TEXT,
    caregiver_id  BIGINT,
    relationship  VARCHAR(50), -- relationship to caregiver (e.g. "daughter", "client", etc.)
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (caregiver_id) REFERENCES caregiver (id) ON DELETE SET NULL
);

-- 3. Billing
CREATE TABLE plan
(
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    price_cents INT NOT NULL,
    billing_period VARCHAR(20) DEFAULT 'MONTH',
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE (code),
    CONSTRAINT plan_chk_1 CHECK ((price_cents >= 0))

);

CREATE TABLE subscription
(
    id                 BIGSERIAL PRIMARY KEY,
    user_id            BIGINT NOT NULL,
    plan_id            BIGINT NOT NULL,
    status             VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'GRACE', 'CANCELLED')),
    started_at         TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    current_period_end TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (plan_id) REFERENCES plan (id)
);

CREATE TABLE payment_method
(
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT,
    provider     VARCHAR(20) NOT NULL CHECK (provider IN ('CARD', 'PAYPAL')),
    stripe_token VARCHAR(255),
    last4        CHAR(4),
    brand        VARCHAR(20),
    exp_month    INT,
    exp_year     INT,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE payment
(
    id                       BIGSERIAL PRIMARY KEY,
    subscription_id          BIGINT      NOT NULL,
    payment_method_id        BIGINT,
    amount_cents             INT         NOT NULL,
    stripe_session_id        VARCHAR(255),
    stripe_payment_intent_id VARCHAR(255),
    status                   VARCHAR(20) NOT NULL CHECK (status IN ('SUCCEEDED', 'FAILED')),
    attempted_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (subscription_id) REFERENCES subscription (id) ON DELETE CASCADE,
    FOREIGN KEY (payment_method_id) REFERENCES payment_method (id) ON DELETE SET NULL
);

CREATE TABLE email_verification_token
(
    id         BIGSERIAL PRIMARY KEY,
    token      VARCHAR(255) NOT NULL UNIQUE,
    user_id    BIGINT,
    expires_at TIMESTAMP    NOT NULL,
    CONSTRAINT fk_email_verification_token_user
        FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE password_reset_token
(
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT       NOT NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP    NOT NULL,
    used       BOOLEAN   DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_password_reset_token_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_password_reset_token_hash ON password_reset_token (token_hash);
CREATE INDEX idx_password_reset_token_expires ON password_reset_token (expires_at);

CREATE TABLE meal_entry
(
    id                BIGSERIAL PRIMARY KEY,
    patient_user_id   BIGINT    NOT NULL,
    caregiver_user_id BIGINT,
    calories          INT CHECK (calories >= 0),
    taken_at          TIMESTAMP NOT NULL,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (caregiver_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX idx_meal_patient_time ON meal_entry (patient_user_id, taken_at);

CREATE TABLE mood_entry
(
    id              BIGSERIAL PRIMARY KEY,
    patient_user_id BIGINT    NOT NULL,
    mood_score      INT CHECK (mood_score BETWEEN 1 AND 5),
    taken_at        TIMESTAMP NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_mood_patient_time ON mood_entry (patient_user_id, taken_at);

CREATE TABLE wearable_metric
(
    id              BIGSERIAL PRIMARY KEY,
    patient_user_id BIGINT           NOT NULL,
    metric          VARCHAR(20)      NOT NULL CHECK (metric IN
                                                     ('HEART_RATE', 'SPO2', 'TEMPERATURE',
                                                      'BLOOD_PRESSURE_SYS', 'BLOOD_PRESSURE_DIA', 'WEIGHT',
                                                      'STEPS')),
    metric_value    DOUBLE PRECISION NOT NULL,
    recorded_at     TIMESTAMP        NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_wearable_patient_time ON wearable_metric (patient_user_id, recorded_at);

CREATE TABLE summary_metrics
(
    id              BIGSERIAL PRIMARY KEY,
    patient_user_id BIGINT    NOT NULL,
    period_start    TIMESTAMP NOT NULL,
    period_end      TIMESTAMP NOT NULL,
    adherence_rate  DOUBLE PRECISION,
    avg_heart_rate  DOUBLE PRECISION,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE,
    UNIQUE (patient_user_id, period_start, period_end)
);

CREATE INDEX idx_summary_patient_end ON summary_metrics (patient_user_id, period_end);

CREATE TABLE symptom_entry
(
    id                BIGSERIAL PRIMARY KEY,
    patient_user_id   BIGINT       NOT NULL,
    caregiver_user_id BIGINT,
    symptom_key       VARCHAR(60)  NOT NULL,
    symptom_value     VARCHAR(255) NOT NULL,
    severity          INT CHECK (severity BETWEEN 1 AND 5),
    taken_at          TIMESTAMP    NOT NULL,
    completed         BOOLEAN   DEFAULT TRUE,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (caregiver_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX idx_symptom_patient_time ON symptom_entry (patient_user_id, taken_at);

CREATE TABLE family_member_link
(
    id              BIGSERIAL PRIMARY KEY,
    family_user_id  BIGINT,
    patient_user_id BIGINT,
    granted_by      BIGINT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (family_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (patient_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (granted_by) REFERENCES users (id) ON DELETE SET NULL
);

CREATE TABLE SPRING_SESSION
(
    PRIMARY_ID            CHAR(36) NOT NULL,
    SESSION_ID            CHAR(36) NOT NULL,
    CREATION_TIME         BIGINT   NOT NULL,
    LAST_ACCESS_TIME      BIGINT   NOT NULL,
    MAX_INACTIVE_INTERVAL INT      NOT NULL,
    EXPIRY_TIME           BIGINT   NOT NULL,
    PRINCIPAL_NAME        VARCHAR(100),
    CONSTRAINT SPRING_SESSION_PK PRIMARY KEY (PRIMARY_ID)
);

CREATE UNIQUE INDEX SPRING_SESSION_IX1 ON SPRING_SESSION (SESSION_ID);
CREATE INDEX SPRING_SESSION_IX2 ON SPRING_SESSION (EXPIRY_TIME);
CREATE INDEX SPRING_SESSION_IX3 ON SPRING_SESSION (PRINCIPAL_NAME);

CREATE TABLE SPRING_SESSION_ATTRIBUTES
(
    SESSION_PRIMARY_ID CHAR(36)     NOT NULL,
    ATTRIBUTE_NAME     VARCHAR(200) NOT NULL,
    ATTRIBUTE_BYTES    BYTEA        NOT NULL,
    CONSTRAINT SPRING_SESSION_ATTRIBUTES_PK PRIMARY KEY (SESSION_PRIMARY_ID, ATTRIBUTE_NAME),
    CONSTRAINT SPRING_SESSION_ATTRIBUTES_FK FOREIGN KEY (SESSION_PRIMARY_ID) REFERENCES SPRING_SESSION (PRIMARY_ID) ON DELETE CASCADE
);

-- Global achievements

CREATE TABLE achievement
(
    id          BIGSERIAL PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    description TEXT,
    icon        VARCHAR(255)
);

-- Earned achievements
CREATE TABLE user_achievements
(
    id             BIGSERIAL PRIMARY KEY,
    user_id        BIGINT NOT NULL,
    achievement_id BIGINT NOT NULL,
    date_earned    TIMESTAMP,
    progress       INT,
    FOREIGN KEY (user_id) REFERENCES users (id),
    FOREIGN KEY (achievement_id) REFERENCES achievement (id)
);
