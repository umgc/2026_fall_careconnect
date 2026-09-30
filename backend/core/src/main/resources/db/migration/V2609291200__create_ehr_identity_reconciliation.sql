-- Phase 2 of the EHR canonical schema: the identity-reconciliation tables.
--
-- Flyway is disabled in every profile; this file is the canonical reference and
-- SchemaPatchRunner.applyEhrIdentityReconciliationPatches() mirrors it for dev and prod.
--
-- created_at/updated_at come from the shared Auditable @MappedSuperclass, which maps them as
-- nullable LocalDateTime (so TIMESTAMP). source_updated_at and detected_at are Instant and
-- therefore TIMESTAMPTZ: they are compared ACROSS sources, and a zone-less type would let a
-- snapshot from another offset appear newer than it is.
--
-- No organization column on any of these three. FR-EHR-10 instructs reuse of an existing
-- organization-identifier isolation pattern; no such column exists anywhere in this schema, so
-- the gap is filed for the Requirements Owner and DE-02 rather than closed with a placeholder.

-- What one source currently believes about a patient. One row per (patient, source), upserted
-- per sync -- NOT appended. The reconciler locks and diffs this row; an append-only history
-- would have nothing stable to lock.
CREATE TABLE IF NOT EXISTS ehr_source_identity (
    id                BIGSERIAL    PRIMARY KEY,
    patient_id        BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    source_id         BIGINT       NOT NULL REFERENCES ehr_source (id),
    source_updated_at TIMESTAMPTZ  NOT NULL,
    given_name        VARCHAR(100),
    family_name       VARCHAR(100),
    date_of_birth     DATE,
    phone             VARCHAR(32),
    email             VARCHAR(254),
    address_line1     VARCHAR(255),
    address_line2     VARCHAR(255),
    city              VARCHAR(100),
    state             VARCHAR(50),
    postal_code       VARCHAR(20),
    -- Stored verbatim, outside the reconciliation vocabulary (2026-09-29): gender is the FHIR code,
    -- not the Gender enum; member_id is not patient.ma_number.
    member_id         VARCHAR(128),
    gender            VARCHAR(16),
    managing_org      VARCHAR(255),
    language          VARCHAR(35),
    created_at        TIMESTAMP,
    updated_at        TIMESTAMP,
    CONSTRAINT uq_ehr_source_identity_patient_source UNIQUE (patient_id, source_id)
);

CREATE INDEX IF NOT EXISTS idx_ehr_source_identity_patient
    ON ehr_source_identity (patient_id);

-- Every disagreement, whether the incoming value won or lost. Recording both outcomes is what
-- makes a bad crosswalk reconstructable after an automatic resolution.
CREATE TABLE IF NOT EXISTS ehr_identity_conflict (
    id                     BIGSERIAL    PRIMARY KEY,
    patient_id             BIGINT       NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    source_id              BIGINT       NOT NULL REFERENCES ehr_source (id),
    field_name             VARCHAR(64)  NOT NULL,
    canonical_value_before TEXT,
    incoming_value         TEXT,
    status                 VARCHAR(16)  NOT NULL,
    resolved_by            VARCHAR(16),
    source_updated_at      TIMESTAMPTZ  NOT NULL,
    detected_at            TIMESTAMPTZ  NOT NULL,
    resolved_at            TIMESTAMPTZ,
    created_at             TIMESTAMP,
    updated_at             TIMESTAMP,

    CONSTRAINT ck_ehr_identity_conflict_status
        CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED')),

    -- No STAFF: every non-DOB field resolves automatically, and the DOB reversal confirmed
    -- patient self-service only.
    CONSTRAINT ck_ehr_identity_conflict_resolver
        CHECK (resolved_by IS NULL OR resolved_by IN ('SYSTEM', 'PATIENT')),

    -- The carve-out, enforced where it cannot be forgotten. A PENDING row for any other field
    -- would silently reintroduce the risk the 2026-09-26 reversal accepted only for non-DOB.
    CONSTRAINT ck_ehr_identity_conflict_pending_dob
        CHECK (status <> 'PENDING' OR field_name = 'date_of_birth'),

    -- Open means unresolved, closed means resolved. No half-states.
    CONSTRAINT ck_ehr_identity_conflict_resolution
        CHECK ((status =  'PENDING' AND resolved_at IS     NULL AND resolved_by IS     NULL)
            OR (status <> 'PENDING' AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_ehr_identity_conflict_patient_field
    ON ehr_identity_conflict (patient_id, field_name);

CREATE INDEX IF NOT EXISTS idx_ehr_identity_conflict_detected_at
    ON ehr_identity_conflict (detected_at);

-- Partial: at most one OPEN conflict per field, while resolved rows accumulate freely.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_identity_conflict_open
    ON ehr_identity_conflict (patient_id, field_name) WHERE status = 'PENDING';

-- Exists for its lock, not its data. IdentityFieldProvenanceStore.lockOrCreate takes
-- SELECT ... FOR UPDATE on (patient_id, field_name) and holds it for the patient read, the
-- conditional write back and the audit row. source_id/source_updated_at are nullable because a
-- row is created empty purely to have something to lock the first time a field is touched;
-- NULL means "no source has established provenance yet".
CREATE TABLE IF NOT EXISTS ehr_identity_field_provenance (
    id                BIGSERIAL   PRIMARY KEY,
    patient_id        BIGINT      NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
    field_name        VARCHAR(64) NOT NULL,
    source_id         BIGINT      REFERENCES ehr_source (id),
    source_updated_at TIMESTAMPTZ,
    created_at        TIMESTAMP,
    updated_at        TIMESTAMP,
    CONSTRAINT uq_ehr_identity_field_provenance_patient_field UNIQUE (patient_id, field_name)
);

-- patient.created_at / updated_at (Patient extends Auditable since 2026-09-29) are added by
-- ddl-auto=update. SchemaPatchRunner V2609291230a..d gives both a DEFAULT now() and backfills
-- existing rows to the migration time; updated_at is the Assumption A1 reconciliation baseline.
