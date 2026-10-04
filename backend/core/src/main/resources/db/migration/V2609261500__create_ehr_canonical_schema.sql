-- Phase 1 of the EHR canonical schema (WBS 1.4.3): source registry, patient crosswalk,
-- raw payload store.
--
-- Flyway is disabled in every profile; this file is the canonical reference and
-- SchemaPatchRunner.applyEhrCanonicalSchemaPatches() mirrors it for dev and prod, the same
-- way the usps_mailpiece and ai_audit_ledger patch methods mirror theirs.
--
-- created_at/updated_at come from the shared Auditable @MappedSuperclass, which maps them as
-- nullable LocalDateTime and populates them in @PrePersist. Hibernate ddl-auto creates those as
-- TIMESTAMP; they are TIMESTAMPTZ here (PR #209 review, 2026-09-30) so the column holds an
-- instant rather than a wall-clock time whose meaning depends on the writer's zone.
-- SchemaPatchRunner.applyEhrAuditTimestampZonePatches() converts what Hibernate created.
--
-- Deliberately carries no organization/tenant column. FR-EHR-10 instructs reuse of an
-- existing organization-identifier isolation pattern, and no such column exists anywhere in
-- this schema; the gap is filed for the Requirements Owner and DE-02 rather than closed with
-- a placeholder column that no query could filter on.

CREATE TABLE IF NOT EXISTS ehr_source (
    id           BIGSERIAL    PRIMARY KEY,
    code         VARCHAR(64)  NOT NULL UNIQUE,
    display_name VARCHAR(128) NOT NULL,
    fhir_version VARCHAR(16)  NOT NULL,
    enabled      BOOLEAN      NOT NULL,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
);

INSERT INTO ehr_source (code, display_name, fhir_version, enabled, created_at, updated_at)
VALUES ('ATHENAHEALTH',  'athenahealth',  'R4', TRUE, now(), now()),
       ('MEDICARE',      'Medicare',      'R4', TRUE, now(), now()),
       ('EPIC',          'Epic',          'R4', TRUE, now(), now()),
       ('ORACLE_HEALTH', 'Oracle Health', 'R4', TRUE, now(), now())
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS ehr_patient_crosswalk (
    id                  BIGSERIAL    PRIMARY KEY,
    patient_id          BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    source_id           BIGINT       NOT NULL REFERENCES ehr_source (id),
    external_patient_id VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ,
    CONSTRAINT uq_ehr_crosswalk_source_external UNIQUE (source_id, external_patient_id),
    CONSTRAINT uq_ehr_crosswalk_patient_source  UNIQUE (patient_id, source_id)
);

CREATE INDEX IF NOT EXISTS idx_ehr_crosswalk_patient
    ON ehr_patient_crosswalk (patient_id);

-- payload holds retrieved clinical content and is PHI-bearing. Inline binary
-- (Patient.photo) is stripped by the caller before insert, never stored then trimmed.
-- retrieved_at is when the source answered; created_at is when this row was written.
CREATE TABLE IF NOT EXISTS ehr_raw_payload (
    id                   BIGSERIAL    PRIMARY KEY,
    patient_id           BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    source_id            BIGINT       NOT NULL REFERENCES ehr_source (id),
    resource_type        VARCHAR(64)  NOT NULL,
    external_resource_id VARCHAR(255),
    payload              JSONB        NOT NULL,
    payload_size_bytes   INTEGER      NOT NULL,
    photo_stripped       BOOLEAN      NOT NULL,
    retrieved_at         TIMESTAMPTZ  NOT NULL,
    created_at           TIMESTAMPTZ,
    updated_at           TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ehr_raw_payload_patient_resource
    ON ehr_raw_payload (patient_id, source_id, resource_type);

CREATE INDEX IF NOT EXISTS idx_ehr_raw_payload_retrieved_at
    ON ehr_raw_payload (retrieved_at);
