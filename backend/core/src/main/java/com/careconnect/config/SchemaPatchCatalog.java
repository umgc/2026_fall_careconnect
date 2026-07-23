package com.careconnect.config;

import java.util.List;

/**
 * Immutable, forward-only production schema patch catalog.
 *
 * <p>Entries must never be reordered, removed, or edited after deployment. Corrections belong
 * in a new resource with a new patch id.
 */
final class SchemaPatchCatalog {

    static final List<SchemaPatchLedger.Patch> PATCHES = List.of(
            new SchemaPatchLedger.Patch(
                    "2607190000-call-transcript-summary-base",
                    "db/migration/V61__create_call_transcript_and_summary_tables.sql"),
            new SchemaPatchLedger.Patch(
                    "2607032251-call-summaries-patient-id",
                    "db/migration/V2607032251__add_patient_id_to_call_summaries.sql"),
            new SchemaPatchLedger.Patch(
                    "2607190001-transcript-archive-base",
                    "db/migration/V63__create_call_transcript_archive_table.sql"),
            new SchemaPatchLedger.Patch(
                    "2607190010-call-summary-idempotency",
                    "db/migration/V2607190010__add_call_summary_generation_idempotency.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191300-transcript-archive-purge",
                    "db/migration/V2607191300__harden_transcript_archive_purge.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191400-summary-citation-replay",
                    "db/migration/V2607190100__create_summary_citation_replay_source.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191500-summary-chunk-ownership-correction",
                    "db/schema-patches/2607191500_summary_chunk_ownership_correction.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191600-transcript-contract",
                    "db/schema-patches/2607191600_transcript_contract.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191700-recording-state",
                    "db/schema-patches/2607191700_recording_state.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191800-termination-steps",
                    "db/schema-patches/2607191800_termination_steps.sql"),
            new SchemaPatchLedger.Patch(
                    "2607191900-chime-attendee-claim",
                    "db/schema-patches/2607191900_chime_attendee_claim.sql"),
            new SchemaPatchLedger.Patch(
                    "2607192000-summary-replay-quarantine-reason",
                    "db/schema-patches/2607192000_summary_replay_quarantine_reason.sql"),
            new SchemaPatchLedger.Patch(
                    "2607211800-ai-held-item",
                    "db/schema-patches/2607211800_create_ai_held_item.sql"));

    private SchemaPatchCatalog() {
    }

    static SchemaPatchLedger.Patch patch(final String id) {
        return PATCHES.stream()
                .filter(candidate -> candidate.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Unknown schema patch: " + id));
    }
}
