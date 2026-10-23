-- CC-12 Emergency Identity & Care Passport, Increment 1: canonical storage for the passport fields
-- that have no existing home, and the patient's per-field opt-in.
--
-- NOTHING EXECUTES THIS FILE. Flyway is disabled in every profile: Hibernate ddl-auto=update
-- creates the tables from the entities, and SchemaPatchRunner.applyEmergencyPassportPatches()
-- adds the unique indexes, foreign keys, the is_public default and the TIMESTAMPTZ conversion on
-- every boot. This file is the readable statement of the intended schema, kept the same way the
-- EHR canonical schema reference is. If it ever disagrees with the entities or the runner, the
-- running database follows them, and this file is the one that is wrong.
--
-- Allergies and medications are not stored here; the passport reads the active rows of
-- patient_allergy and patient_medication. The QR token table is Increment 2.
--
-- The foreign keys carry the names SchemaPatchRunner gives them. Hibernate also adds a CHECK
-- constraint to each enum column when it creates the table (blood_type: the eight BloodType names;
-- field_key: the five PassportField names). ddl-auto=update never alters those, so adding an enum
-- value later needs a patch that drops and recreates the CHECK, as V75 does for user_files.

-- One row per patient. Every value column is nullable: a patient may fill in any subset.
-- chronic_conditions is a single free-text summary (reduced M4 scope); a structured per-condition
-- table is a later change.
CREATE TABLE IF NOT EXISTS emergency_passport_profile (
    id                             BIGSERIAL    PRIMARY KEY,
    patient_id                     BIGINT       NOT NULL
        CONSTRAINT fk_emergency_passport_profile_patient REFERENCES patient (id) ON DELETE CASCADE,
    blood_type                     VARCHAR(16),           -- BloodType enum name, e.g. O_NEGATIVE
    chronic_conditions             TEXT,
    emergency_contact_name         VARCHAR(255),
    emergency_contact_phone        VARCHAR(32),
    emergency_contact_relationship VARCHAR(64),
    created_at                     TIMESTAMPTZ,
    updated_at                     TIMESTAMPTZ,
    CONSTRAINT uq_emergency_passport_profile_patient UNIQUE (patient_id)
);

-- The opt-in switch, one row per (patient, field). A missing row means hidden, the same as
-- is_public = FALSE; nothing is public by default.
CREATE TABLE IF NOT EXISTS emergency_passport_field_visibility (
    id         BIGSERIAL   PRIMARY KEY,
    patient_id BIGINT      NOT NULL
        CONSTRAINT fk_emergency_passport_visibility_patient REFERENCES patient (id) ON DELETE CASCADE,
    field_key  VARCHAR(30) NOT NULL,  -- ALLERGIES, MEDICATIONS, CHRONIC_CONDITIONS, BLOOD_TYPE, EMERGENCY_CONTACT
    is_public  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    CONSTRAINT uq_emergency_passport_visibility_patient_field UNIQUE (patient_id, field_key)
);
