-- EHR identity reconciliation constraints and indexes.
--
-- Hibernate ddl-auto creates ehr_source, ehr_source_identity, and ehr_identity_conflict from
-- their entities during context refresh, before this patch runs. No CREATE TABLE appears here
-- on purpose: it would no-op against the Hibernate-created table while the ledger recorded the
-- patch as applied, the same failure that hid the recording-worker audit columns.
--
-- ScriptUtils splits on ';' and cannot execute dollar-quoted blocks, so constraint idempotency
-- is expressed as DROP IF EXISTS followed by ADD rather than a DO $$ ... $$ guard.
--
-- The single-column value domains for status and resolved_by are NOT declared here: both are
-- @Enumerated(EnumType.STRING) fields, so Hibernate already emits
-- ehr_identity_conflict_status_check and ehr_identity_conflict_resolved_by_check. Declaring
-- them again would leave two constraints per column, each needing an update whenever the enum
-- gains a value. Only the cross-column rule Hibernate cannot express belongs here.

-- One snapshot per (patient, source). This is the idempotency key that lets an adapter safely
-- re-run an interrupted sync, so it is enforced in the database rather than only in code.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_source_identity_patient_source
  ON ehr_source_identity (patient_id, source_id);

-- A resolved conflict must carry both who and when; a pending one must carry neither. Without
-- this a half-written resolution reads as unresolved and re-prompts the patient forever.
ALTER TABLE ehr_identity_conflict
  DROP CONSTRAINT IF EXISTS ck_ehr_identity_conflict_resolution;
ALTER TABLE ehr_identity_conflict
  ADD CONSTRAINT ck_ehr_identity_conflict_resolution
  CHECK ((status = 'PENDING' AND resolved_at IS NULL AND resolved_by IS NULL)
      OR (status <> 'PENDING' AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL));

-- At most one open conflict per field, so repeated syncs of an unresolved field do not stack
-- duplicate prompts. Also serves the UI's pending-conflicts lookup, since patient_id leads the
-- index and the predicate matches.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_identity_conflict_open
  ON ehr_identity_conflict (patient_id, source_id, field_name)
  WHERE status = 'PENDING';
