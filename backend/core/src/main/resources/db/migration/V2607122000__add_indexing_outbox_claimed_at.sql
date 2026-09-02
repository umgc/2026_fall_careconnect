-- V2607122000__add_indexing_outbox_claimed_at.sql
--
-- Durable claim lease for IndexWorker (multi-ECS safe).
-- FOR UPDATE SKIP LOCKED alone only holds during the claim transaction;
-- claimed_at keeps other workers from picking the same unprocessed row
-- until the lease expires (default 2 minutes) or the row is completed.

ALTER TABLE indexing_outbox
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NULL;

COMMENT
ON COLUMN indexing_outbox.claimed_at IS
    'Set when IndexWorker claims a row; cleared on process/fail/defer. '
    'Rows with a fresh claimed_at are skipped by other workers until lease expiry.';

CREATE INDEX IF NOT EXISTS idx_indexing_outbox_claimable
    ON indexing_outbox (id ASC)
    WHERE processed_at IS NULL;
