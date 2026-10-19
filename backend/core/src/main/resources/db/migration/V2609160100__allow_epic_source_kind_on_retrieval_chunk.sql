-- Allow Epic FHIR retrieval chunks to be indexed for Ask AI.
--
-- The Epic indexer (EpicResourceChunker / RetrievalIndexService) writes
-- retrieval_index_chunk rows with source_kind = 'epic', but ck_retrieval_source_kind
-- (added in V2607190100) only permitted 'CALL_SUMMARY' / 'VISIT_SUMMARY'. As a result
-- every EPIC_FHIR_INDEXED outbox event failed with:
--   ERROR: new row for relation "retrieval_index_chunk" violates check constraint
--          "ck_retrieval_source_kind"
-- and no Epic record was ever indexed, so Ask AI could not retrieve or cite them.
--
-- Widen the allow-list to include the Epic discriminator. Both casings are permitted
-- defensively: EpicProperties.SOURCE_EPIC is "EPIC" (uppercase) while the chunk row is
-- currently written as lowercase 'epic' — that casing inconsistency should be reconciled
-- separately in the indexer.
--
-- NOTE: spring.flyway.enabled=false in this project (SchemaPatchRunner runs on boot and
-- only verifies this constraint exists), so this change was also applied to the running
-- database manually via the equivalent ALTER.

ALTER TABLE retrieval_index_chunk
    DROP CONSTRAINT IF EXISTS ck_retrieval_source_kind;

ALTER TABLE retrieval_index_chunk
    ADD CONSTRAINT ck_retrieval_source_kind
        CHECK (source_kind IS NULL OR source_kind IN (
            'CALL_SUMMARY', 'VISIT_SUMMARY', 'EPIC', 'epic'));
