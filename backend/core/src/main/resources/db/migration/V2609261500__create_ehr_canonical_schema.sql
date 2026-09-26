-- Phase 1 of the EHR canonical schema (WBS 1.4.3): source registry, patient crosswalk,
-- raw payload store.
--
-- Flyway is disabled in every profile; this file is the canonical reference and
-- SchemaPatchRunner.applyEhrCanonicalSchemaPatches() mirrors it for dev and prod.
--
-- Deliberately carries no organization/tenant column. FR-EHR-10 instructs reuse of an
-- existing organization-identifier isolation pattern, and no such column exists anywhere in
-- this schema; the gap is filed for the Requirements Owner and DE-02 rather than closed with
-- a placeholder column that no query could filter on.

CREATE TABLE IF NOT EXISTS ehr_source (
    id           BIGSERIAL    PRIMARY KEY,
    code         VARCHAR(64)  NOT NULL UNIQUE,
    display_name VARCHAR(128) NOT NULL,
    enabled      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

INSERT INTO ehr_source (code, display_name)
VALUES ('ATHENAHEALTH',  'athenahealth'),
       ('MEDICARE',      'Medicare'),
       ('EPIC',          'Epic'),
       ('ORACLE_HEALTH', 'Oracle Health')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS ehr_patient_crosswalk (
    id                  BIGSERIAL    PRIMARY KEY,
    patient_id          BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    source_id           BIGINT       NOT NULL REFERENCES ehr_source (id),
    external_patient_id VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_ehr_crosswalk_source_external UNIQUE (source_id, external_patient_id),
    CONSTRAINT uq_ehr_crosswalk_patient_source  UNIQUE (patient_id, source_id)
);

CREATE INDEX IF NOT EXISTS idx_ehr_crosswalk_patient
    ON ehr_patient_crosswalk (patient_id);

-- payload holds retrieved clinical content and is PHI-bearing. Inline binary
-- (Patient.photo) is stripped by the caller before insert, never stored then trimmed.
CREATE TABLE IF NOT EXISTS ehr_raw_payload (
    id                   BIGSERIAL    PRIMARY KEY,
    patient_id           BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    source_id            BIGINT       NOT NULL REFERENCES ehr_source (id),
    resource_type        VARCHAR(64)  NOT NULL,
    external_resource_id VARCHAR(255),
    payload              JSONB        NOT NULL,
    payload_size_bytes   INTEGER      NOT NULL,
    photo_stripped       BOOLEAN      NOT NULL DEFAULT FALSE,
    retrieved_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ehr_raw_payload_patient_resource
    ON ehr_raw_payload (patient_id, source_id, resource_type);

CREATE INDEX IF NOT EXISTS idx_ehr_raw_payload_retrieved_at
    ON ehr_raw_payload (retrieved_at);
