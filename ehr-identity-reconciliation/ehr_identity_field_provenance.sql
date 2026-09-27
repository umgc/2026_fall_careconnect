-- New table required by the shared identity-reconciliation library (com.careconnect.ehr.reconciliation).
-- Not designed in either original draft -- see README.md "Why this table exists". It is the durable,
-- lockable "who's currently freshest for this field" record that the reconciliation algorithm's
-- concurrency guarantee depends on (IdentityFieldProvenanceStore.lockOrCreate takes SELECT ... FOR
-- UPDATE against this table's row).
--
-- TODO before this ships: replace `org_id BIGINT` below with whatever the ACTUAL organization-scoping
-- column on `patient`/`users` is really named and typed (see the Decisions log in
-- EHR_Canonical_Schema_Validation_and_Implementation_Plan.md, Phase 0 item 1 -- still not confirmed in
-- this environment). Do not ship this literally as `org_id BIGINT` without checking.

CREATE TABLE ehr_identity_field_provenance
(
    id                BIGSERIAL PRIMARY KEY,
    patient_id        BIGINT       NOT NULL REFERENCES patient (id),
    org_id            BIGINT       NOT NULL, -- TODO: match patient's real tenant column, see above
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
CREATE INDEX idx_ehr_identity_field_provenance_org ON ehr_identity_field_provenance (org_id);

-- Usage note for IdentityFieldProvenanceStore.lockOrCreate(patientId, orgId, fieldName):
--   INSERT INTO ehr_identity_field_provenance (patient_id, org_id, field_name)
--     VALUES (:patientId, :orgId, :fieldName)
--     ON CONFLICT (patient_id, field_name) DO NOTHING;
--   SELECT source_id, source_updated_at
--     FROM ehr_identity_field_provenance
--     WHERE patient_id = :patientId AND field_name = :fieldName
--     FOR UPDATE;
--   -- source_id/source_updated_at both NULL => return Optional.empty() to the caller.
-- The row lock from FOR UPDATE must be held on the same connection/transaction for the rest of the
-- field's processing (patient read+write, audit-row write) -- see TransactionRunner's javadoc.
