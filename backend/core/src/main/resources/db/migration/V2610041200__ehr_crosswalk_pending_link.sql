-- A crosswalk row now exists while a link is pending, before the source has said who the patient
-- is, and it carries that source's tokens.
--
-- These changes were first made by editing V2609261500__create_ehr_canonical_schema.sql, and that
-- edit reached develop when #287 merged (2026-10-09). An applied migration must never change: Flyway
-- validate fails on the new checksum for every database that already ran it (#287 review). So
-- V2609261500 is back to the text develop carried from #216 (2026-10-02), and the changes live here.
-- A database that ran flyway:migrate from develop after #287 merged holds the edited file's checksum:
-- run flyway:repair once, then flyway:migrate.
--
-- Production does not run Flyway; SchemaPatchRunner applies the nullability change there
-- (V2610041200a) and Hibernate ddl-auto adds the columns. Every statement is safe to rerun.

ALTER TABLE ehr_patient_crosswalk ALTER COLUMN external_patient_id DROP NOT NULL;

ALTER TABLE ehr_patient_crosswalk
    ADD COLUMN IF NOT EXISTS token                 VARCHAR(255),  -- encrypted at rest (TokenCryptor)
    ADD COLUMN IF NOT EXISTS refresh_token         VARCHAR(255),  -- encrypted at rest (TokenCryptor)
    ADD COLUMN IF NOT EXISTS token_expires_at      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_logged_in        TIMESTAMP,
    ADD COLUMN IF NOT EXISTS last_refreshed        TIMESTAMP,
    ADD COLUMN IF NOT EXISTS link_token            VARCHAR(255),  -- one-time, null once the link completes
    ADD COLUMN IF NOT EXISTS link_token_expires_at TIMESTAMPTZ;

ALTER TABLE ehr_patient_crosswalk DROP CONSTRAINT IF EXISTS uq_ehr_crosswalk_link_token;
ALTER TABLE ehr_patient_crosswalk ADD CONSTRAINT uq_ehr_crosswalk_link_token UNIQUE (link_token);
