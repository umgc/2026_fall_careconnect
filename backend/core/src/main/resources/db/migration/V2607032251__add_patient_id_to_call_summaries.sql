-- V2607032251__add_patient_id_to_call_summaries.sql
--
-- Adds patient_id to call_summaries to scope summaries by patient
-- for RBAC checks at the Ask AI indexing pipeline (WBS 3.11.5, #190).
--
-- Nullable to support historic rows that predate this column; new
-- summaries populate it from the call context (telemetry CALL_JOIN
-- -> patient association) at persistence time.
--
-- Ravichandra Vasireddy agreed on 2026-07-03 that carrying patient_id
-- as a first-class column is cleaner than resolving via JOIN on every
-- SUMMARY_CREATED emit.

ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS patient_id BIGINT NULL;

CREATE INDEX IF NOT EXISTS idx_call_summary_patient_id
    ON call_summaries (patient_id);

COMMENT ON COLUMN call_summaries.patient_id IS
    'Patient this summary is about. Nullable for historic rows; populated for new summaries via telemetry at persist time. Correlation key for Ask AI RBAC-scoped retrieval.';