-- Quarantine reason + attempt bound metadata for summary citation replay.
ALTER TABLE summary_citation_replay_source
    ADD COLUMN IF NOT EXISTS quarantine_reason VARCHAR(255);

COMMENT ON COLUMN summary_citation_replay_source.quarantine_reason IS
    'Terminal quarantine reason when migration_status = QUARANTINED';

UPDATE summary_citation_replay_source
SET quarantine_reason = NULL
WHERE migration_status = 'ACTIVE'
  AND quarantine_reason IS NOT NULL;
