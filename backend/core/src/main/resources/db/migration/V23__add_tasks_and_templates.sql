-- V10__add_tasks_and_templates.sql
-- Add tasks and templates functionality for patients

CREATE TABLE tasks (
    id BIGSERIAL PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    date TIMESTAMP NOT NULL,
    time_of_day TIME NOT NULL,
    isCompleted BOOLEAN NOT NULL DEFAULT FALSE,
    task_type VARCHAR(20) NOT NULL CHECK (task_type IN ('TASK', 'FREQUENCY', 'DAYOFWEEK')),
    frequency TEXT,
    task_interval INT,
    do_count INT,
    days_of_week JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'COMPLETED')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE templates (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    frequency TEXT,
    task_interval INT,
    do_count INT,
    days_of_week JSONB,
    time_of_day TIME,
    icon VARCHAR(255) NOT NULL,
    notifications JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
