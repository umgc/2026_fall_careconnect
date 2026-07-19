package com.careconnect.config;

import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;

import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SchemaPatchCatalogTest {

    @Test
    void catalog_keepsPrerequisitesBeforeDependentPatches() {
        final List<String> ids = SchemaPatchCatalog.PATCHES.stream()
                .map(SchemaPatchLedger.Patch::id)
                .toList();

        assertThat(ids).containsExactly(
                "2607190000-call-transcript-summary-base",
                "2607032251-call-summaries-patient-id",
                "2607190001-transcript-archive-base",
                "2607190010-call-summary-idempotency",
                "2607191300-transcript-archive-purge",
                "2607191400-summary-citation-replay",
                "2607191500-summary-chunk-ownership-correction",
                "2607191600-transcript-contract",
                "2607191700-recording-state",
                "2607191800-termination-steps",
                "2607191900-chime-attendee-claim",
                "2607192000-summary-replay-quarantine-reason");
    }

    @Test
    void ownershipCorrection_requiresCanonicalIdAndMatchingPatient() throws Exception {
        final String sql = new ClassPathResource(
                "db/schema-patches/2607191500_summary_chunk_ownership_correction.sql")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(sql)
                .contains("ric.source_record_id ~ '^call-summary:[0-9]+$'")
                .contains("cs.patient_id = ric.patient_id")
                .contains("migration_status = 'QUARANTINED'")
                .contains("JOIN call_summaries cs")
                .contains("ON CONFLICT (patient_id, source_kind, source_record_id)");
    }

    @Test
    void transcriptContract_isLedgeredAndIdempotent() throws Exception {
        final String sql = new ClassPathResource(
                "db/schema-patches/2607191600_transcript_contract.sql")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(sql)
                .contains("client_segment_id UUID")
                .contains("WHERE client_segment_id IS NOT NULL")
                .contains("dead_lettered_at TIMESTAMPTZ")
                .contains("terminal_error VARCHAR(1000)");
    }

    @Test
    void recordingState_failsClosedBeforeAddingActiveUniqueIndex() throws Exception {
        final String sql = new ClassPathResource(
                "db/schema-patches/2607191700_recording_state.sql")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(sql)
                .contains("duplicate active AWS-capable rows exist")
                .contains("uq_call_recordings_active_generation")
                .contains("recording_compensation_outbox")
                .contains("post_call_transcription_jobs");
    }

    @Test
    void terminationSteps_addIndependentProgressTimestamps() throws Exception {
        final String sql = new ClassPathResource(
                "db/schema-patches/2607191800_termination_steps.sql")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(sql)
                .contains("termination_sentiment_at")
                .contains("termination_summary_at")
                .contains("termination_recording_at")
                .contains("termination_meeting_at");
    }

    @Test
    void chimeAttendeeClaim_addsDurableClaimAndResultColumns() throws Exception {
        final String sql = new ClassPathResource(
                "db/schema-patches/2607191900_chime_attendee_claim.sql")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(sql)
                .contains("chime_external_user_id")
                .contains("chime_attendee_id")
                .contains("chime_join_token")
                .contains("attendee_claim_token")
                .contains("attendee_claimed_until");
    }

    @Test
    void summaryReplayQuarantineReason_isLedgered() throws Exception {
        final String sql = new ClassPathResource(
                "db/schema-patches/2607192000_summary_replay_quarantine_reason.sql")
                .getContentAsString(StandardCharsets.UTF_8);

        assertThat(sql)
                .contains("quarantine_reason VARCHAR(255)")
                .contains("summary_citation_replay_source");
    }
}
