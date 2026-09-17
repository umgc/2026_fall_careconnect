-- V2607032257__create_indexing_outbox.sql
--
-- Transactional outbox for indexing events emitted by the summaries
-- workstream and consumed by the Ask AI upstream indexing pipeline.
-- Per the 2026-07-03 Transcript Ingest and SUMMARY_CREATED Indexing
-- Contract from Ravichandra Vasireddy.
--
-- Ownership boundary:
--   Fon writes rows in the same @Transactional method that persists a
--   CallSummary (SUMMARY_CREATED) or a transcript segment batch
--   (TRANSCRIPT_INDEXED), so the event and the source record commit
--   or roll back together.
--   Ravi's side (backlog 3.4) polls processed_at IS NULL rows in
--   insertion order, publishes to SNS, and stamps processed_at on
--   success. IndexWorker (backlog 1.5) consumes from SQS and writes
--   to retrieval_index_chunk.
--
-- Related: WBS 3.11.5 emit (#190), 3.11.1 transcript emit (#186),
--          backlog 3.4 poller, backlog 1.5 retrieval index.

CREATE TABLE IF NOT EXISTS indexing_outbox (
    id             BIGSERIAL   PRIMARY KEY,
    event_type     VARCHAR(64) NOT NULL,
    payload_json   TEXT        NOT NULL,
    created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at   TIMESTAMP   NULL,
    attempt_count  INTEGER     NOT NULL DEFAULT 0,
    last_error     TEXT        NULL
);

-- Poller reads unprocessed rows in insertion order. Partial index keeps
-- the working set tiny once the backlog is drained.
CREATE INDEX IF NOT EXISTS idx_indexing_outbox_unprocessed
    ON indexing_outbox (created_at)
    WHERE processed_at IS NULL;

-- General index for debugging queries by event type.
CREATE INDEX IF NOT EXISTS idx_indexing_outbox_event_type
    ON indexing_outbox (event_type);

COMMENT ON TABLE indexing_outbox IS
    'Transactional outbox for indexing events (WBS 3.11.5 emit, backlog 3.4 poller). Rows written in the same transaction as summary/transcript persistence; poller stamps processed_at on successful SNS publish.';

COMMENT ON COLUMN indexing_outbox.event_type IS
    'Event type discriminator: SUMMARY_CREATED | TRANSCRIPT_INDEXED (extensible to future types).';

COMMENT ON COLUMN indexing_outbox.payload_json IS
    'Full event envelope as JSON: {eventType, eventId, occurredAt, schemaVersion, payload: {...}}. Consumers use eventId for idempotency.';

COMMENT ON COLUMN indexing_outbox.processed_at IS
    'NULL until the poller successfully publishes to SNS. Poller filters on this column.';

COMMENT ON COLUMN indexing_outbox.attempt_count IS
    'Retry counter incremented by the poller on each publish attempt (backoff / DLQ signal).';