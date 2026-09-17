-- Forward correction for typed summary ownership. A canonical call-summary source is
-- retrieval-eligible only when its id and patient agree with call_summaries.
UPDATE retrieval_index_chunk ric
SET migration_status = 'QUARANTINED',
    citation_replay_claimed_until = NULL,
    citation_replay_claim_token = NULL
WHERE ric.migration_status = 'ACTIVE'
  AND ric.record_type IN (
    'CALL_SUMMARY', 'VISIT_SUMMARY', 'SUMMARY_ACTION_ITEM',
    'SUMMARY_APPOINTMENT', 'SUMMARY_CARE_INSTRUCTION',
    'SUMMARY_CONDITION', 'SUMMARY_SOAP', 'SUMMARY_CLINICAL_OBSERVATION')
  AND NOT (
    ric.source_kind = 'CALL_SUMMARY'
    AND ric.source_record_id ~ '^call-summary:[0-9]+$'
    AND EXISTS (
      SELECT 1
      FROM call_summaries cs
      WHERE ric.source_record_id = 'call-summary:' || cs.id::text
        AND cs.patient_id = ric.patient_id
    )
  );

-- Previously registered sources may have predated authoritative ownership validation.
UPDATE summary_citation_replay_source replay
SET migration_status = 'QUARANTINED',
    claimed_until = NULL,
    claim_token = NULL,
    updated_at = now()
WHERE replay.migration_status = 'ACTIVE'
  AND (
    replay.source_kind <> 'CALL_SUMMARY'
    OR replay.source_record_id !~ '^call-summary:[0-9]+$'
    OR NOT EXISTS (
      SELECT 1
      FROM call_summaries cs
      WHERE replay.source_record_id = 'call-summary:' || cs.id::text
        AND cs.patient_id = replay.patient_id
    )
  );

-- Register only active chunks whose canonical source has matching patient ownership.
INSERT INTO summary_citation_replay_source (
    patient_id, source_kind, source_record_id, migration_status)
SELECT DISTINCT ric.patient_id, 'CALL_SUMMARY', ric.source_record_id, 'ACTIVE'
FROM retrieval_index_chunk ric
JOIN call_summaries cs
  ON ric.source_record_id = 'call-summary:' || cs.id::text
 AND cs.patient_id = ric.patient_id
WHERE ric.migration_status = 'ACTIVE'
  AND ric.source_kind = 'CALL_SUMMARY'
  AND ric.source_record_id ~ '^call-summary:[0-9]+$'
ON CONFLICT (patient_id, source_kind, source_record_id)
DO UPDATE SET migration_status = 'ACTIVE', updated_at = now();
