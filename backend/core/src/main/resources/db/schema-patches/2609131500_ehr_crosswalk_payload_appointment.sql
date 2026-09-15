-- EHR patient crosswalk, raw payload, and appointment record constraints and indexes.
--
-- Hibernate ddl-auto creates ehr_patient_crosswalk, ehr_raw_payload, and ehr_appointment_record
-- from their entities during context refresh, before this patch runs. No CREATE TABLE appears
-- here on purpose, matching 2609121200_ehr_identity_reconciliation.sql: it would no-op against
-- the Hibernate-created table while the ledger recorded the patch as applied.
--
-- ScriptUtils splits on ';' and cannot execute dollar-quoted blocks, so idempotency is expressed
-- as CREATE ... IF NOT EXISTS rather than a DO $$ ... $$ guard.

-- Decision 2 (EHR_Canonical_Schema_Draft.md): one external identity maps to at most one internal
-- patient.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_patient_crosswalk_source_external
  ON ehr_patient_crosswalk (source_id, external_patient_id);

-- Decision 2: one external id per patient per source. Flagged in the draft as an assumption — if
-- a source can expose multiple identifiers for one patient, this constraint needs to relax to
-- allow multiples, not the one above.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_patient_crosswalk_patient_source
  ON ehr_patient_crosswalk (patient_id, source_id);

-- One raw payload row per fetched resource; a re-fetch updates it in place instead of stacking
-- duplicate raw copies. Backs EhrRawPayloadRepository's upsert lookup.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_raw_payload_resource
  ON ehr_raw_payload (patient_id, source_id, resource_type, external_resource_id);

-- One appointment row per (patient, source, external_appointment_id); a re-sync updates it in
-- place instead of stacking duplicates. Backs EhrAppointmentRecordRepository's upsert lookup.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ehr_appointment_record_external
  ON ehr_appointment_record (patient_id, source_id, external_appointment_id);
