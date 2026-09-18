-- Predefined risk types (standard list for all clients)
CREATE TABLE risk_types (
    id   BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

-- Which risks are flagged for a given patient (client)
CREATE TABLE patient_risks (
    id            BIGSERIAL PRIMARY KEY,
    patient_id    BIGINT NOT NULL,
    risk_type_id  BIGINT NOT NULL,
    flagged_by    BIGINT NOT NULL,
    flagged_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_patient_risks_patient   FOREIGN KEY (patient_id)   REFERENCES patient (id) ON DELETE CASCADE,
    CONSTRAINT fk_patient_risks_risk_type  FOREIGN KEY (risk_type_id) REFERENCES risk_types (id) ON DELETE CASCADE,
    CONSTRAINT fk_patient_risks_user      FOREIGN KEY (flagged_by)   REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT uq_patient_risk UNIQUE (patient_id, risk_type_id)
);

CREATE INDEX idx_patient_risks_patient ON patient_risks (patient_id);

-- Seed the 5 predefined risk types
INSERT INTO risk_types (name) VALUES
    ('Aspiration Pneumonia'),
    ('Elopement'),
    ('Fall with Injury'),
    ('Self-Harm'),
    ('Seizures');
