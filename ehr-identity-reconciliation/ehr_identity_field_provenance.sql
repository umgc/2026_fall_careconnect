-- New table required by the shared identity-reconciliation library (com.careconnect.ehr.reconciliation).
-- Not designed in either original draft -- see README.md "Why this table exists". It is the durable,
-- lockable "who's currently freshest for this field" record that the reconciliation algorithm's
-- concurrency guarantee depends on (IdentityFieldProvenanceStore.lockOrCreate takes SELECT ... FOR
-- UPDATE against this table's row).
--
-- Carries no organization-scoping column. An earlier draft had `org_id BIGINT NOT NULL` with a TODO to
-- match whatever `patient`/`users` really use; that premise turned out to be false. `org_id`,
-- `organization_id` and `tenant_id` appear nowhere in this codebase -- not on `patient`, `users` or
-- `caregiver` -- so there was nothing to match and nothing that could have populated a NOT NULL column.
-- See the plan's 2026-09-26 org-scoping reversal. `orgId` was removed from the library's interfaces at
-- the same time, for the same reason.

CREATE TABLE ehr_identity_field_provenance
(
    id                BIGSERIAL PRIMARY KEY,
    patient_id        BIGINT       NOT NULL REFERENCES patient (id),
    field_name        VARCHAR(64)  NOT NULL, -- same field_name vocabulary as ehr_identity_conflict
    -- Nullable: a row is created empty (both NULL) purely to have something to lock the first time a
    -- field is touched. NULL here means "no source has established provenance for this field yet" and
    -- must map to Optional.empty() in IdentityFieldProvenanceStore.lockOrCreate, matching the "no
    -- provenance -> fall back to patient.updated_at" rule (Assumption A1) in RecencyWinsIdentityReconciler.
    source_id         BIGINT       REFERENCES ehr_source (id),
    source_updated_at TIMESTAMP,
    created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_ehr_identity_field_provenance_patient_field UNIQUE (patient_id, field_name)
);

CREATE INDEX idx_ehr_identity_field_provenance_patient ON ehr_identity_field_provenance (patient_id);

-- Usage note for IdentityFieldProvenanceStore.lockOrCreate(patientId, fieldName):
--   INSERT INTO ehr_identity_field_provenance (patient_id, field_name)
--     VALUES (:patientId, :fieldName)
--     ON CONFLICT (patient_id, field_name) DO NOTHING;
--   SELECT source_id, source_updated_at
--     FROM ehr_identity_field_provenance
--     WHERE patient_id = :patientId AND field_name = :fieldName
--     FOR UPDATE;
--   -- source_id/source_updated_at both NULL => return Optional.empty() to the caller.
-- The row lock from FOR UPDATE must be held on the same connection/transaction for the rest of the
-- field's processing (patient read+write, audit-row write) -- see TransactionRunner's javadoc.
