package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallRecording;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.model.conditiondetection.ConditionDetectionContext;
import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.service.BedrockSentimentService;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Validates the Phase 2 transcript screening adapter: waiting for transcription, using only
 * KVS segments (speaker known from the stream) and never live captions (actor = uploader),
 * refusing to screen when no line is attributed to the patient, sending the whole conversation
 * as an anonymized role-tagged transcript in budget-sized chunks, merging chunk results, and
 * strictly validating the model's JSON. Bedrock, the transcript store and the
 * recording repository are mocked so the suite needs no AWS access or database.
 */
@ExtendWith(MockitoExtension.class)
class BedrockTranscriptScreeningAdapterTest {

    private static final String CALL_ID = "call-1";
    private static final long PATIENT_USER_ID = 42L;
    private static final long CAREGIVER_USER_ID = 7L;
    private static final long RECORDING_ID = 9L;

    private static final String VALID_REPLY = """
            {"conditions":[
              {"condition":"PTSD","indicator_level":"moderate","evidence_summary":"Describes recurring nightmares."},
              {"condition":"BIPOLAR","indicator_level":"NONE","evidence_summary":"No relevant statements."}]}
            """;

    @Mock
    private BedrockSentimentService bedrock;
    @Mock
    private CallTranscriptService transcriptService;
    @Mock
    private CallRecordingRepository recordingRepository;

    private BedrockTranscriptScreeningAdapter adapter;

    @BeforeEach
    void setUp() {
        adapter = new BedrockTranscriptScreeningAdapter(
                bedrock, transcriptService, recordingRepository, new ObjectMapper(), "");
    }

    private static ConditionDetectionContext context(final LocalDateTime createdAt) {
        return new ConditionDetectionContext(CALL_ID, 5L, PATIENT_USER_ID, RECORDING_ID, createdAt);
    }

    private static ConditionDetectionContext freshContext() {
        return context(LocalDateTime.now(ZoneOffset.UTC));
    }

    private void transcriptionStatus(final String status) {
        final CallRecording recording = new CallRecording();
        recording.setTranscriptionStatus(status);
        when(recordingRepository.findById(RECORDING_ID)).thenReturn(Optional.of(recording));
    }

    /** A per-attendee KVS segment: the actor is the speaker. */
    private static CallTranscriptSegment kvs(final Long speaker, final long startMs, final String text) {
        return ConditionDetectionFixtures.transcriptSegment(
                speaker, ConditionDetectionFixtures.KVS_SOURCE, startMs, text);
    }

    /** A live caption: the actor is whoever's client uploaded it, not necessarily the speaker. */
    private static CallTranscriptSegment caption(final Long uploader, final long startMs, final String text) {
        return ConditionDetectionFixtures.transcriptSegment(
                uploader, ConditionDetectionFixtures.LIVE_CAPTION_SOURCE, startMs, text);
    }

    private void transcriptReady(final List<CallTranscriptSegment> segments) {
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("COMPLETE");
        when(transcriptService.getSegmentsForCall(CALL_ID)).thenReturn(segments);
    }

    /** Registry metadata: id, conditions, and a config version that records model plus prompt version. */
    @Test
    void identity_describesTranscriptModelForPtsdAndBipolar() {
        when(bedrock.resolveTextModelId(null)).thenReturn("amazon.nova-lite-v1:0");

        assertThat(adapter.modelId()).isEqualTo(BedrockTranscriptScreeningAdapter.MODEL_ID);
        assertThat(adapter.supportedConditions()).containsExactlyInAnyOrder(ConditionName.PTSD, ConditionName.BIPOLAR);
        assertThat(adapter.configVersion()).isEqualTo("amazon.nova-lite-v1:0:condition-screen-v2");
    }

    /** Local/test environments without Bedrock skip instead of retrying forever. */
    @Test
    void analyze_skipsWhenBedrockUnavailable() throws Exception {
        when(bedrock.canInvokeBedrock()).thenReturn(false);

        assertThat(adapter.analyze(freshContext()))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.MODEL_UNAVAILABLE));
    }

    /** Transcription still running: re-queue without reading the transcript. */
    @Test
    void analyze_defersWhileTranscriptionIsProcessing() throws Exception {
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("PROCESSING");

        assertThat(adapter.analyze(freshContext())).isEqualTo(
                new AdapterOutcome.Deferred(BedrockTranscriptScreeningAdapter.TRANSCRIPT_POLL_SECONDS));
        verify(transcriptService, never()).getSegmentsForCall(anyString());
    }

    /** Seven hours waiting (one past the six-hour limit) gives up with TRANSCRIPT_TIMEOUT. */
    @Test
    void analyze_timesOutAfterWaitingTooLong() throws Exception {
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("READY");

        assertThat(adapter.analyze(context(LocalDateTime.now(ZoneOffset.UTC).minusHours(7))))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.TRANSCRIPT_TIMEOUT));
    }

    /** A failed transcription can never produce a transcript, so skip permanently. */
    @Test
    void analyze_skipsWhenTranscriptionFailed() throws Exception {
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("FAILED");

        assertThat(adapter.analyze(freshContext()))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.TRANSCRIPT_UNAVAILABLE));
    }

    /** No recording means no post-call transcript. */
    @Test
    void analyze_skipsWithoutRecording() throws Exception {
        when(bedrock.canInvokeBedrock()).thenReturn(true);

        assertThat(adapter.analyze(new ConditionDetectionContext(CALL_ID, 5L, PATIENT_USER_ID, null, null)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.TRANSCRIPT_UNAVAILABLE));
    }

    /** Mixed-recording (no actor) and caregiver-only KVS lines cannot be attributed to the patient, so Bedrock is never called. */
    @Test
    void analyze_skipsWhenNoLineIsAttributedToThePatient() throws Exception {
        transcriptReady(List.of(
                ConditionDetectionFixtures.transcriptSegment(
                        null, "POST_CALL_MP4_MIXED", 0L, "Mixed-recording line with no attendee"),
                kvs(CAREGIVER_USER_ID, 1_000L, "How have you been sleeping?")));

        assertThat(adapter.analyze(freshContext()))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.PATIENT_SPEAKER_UNIDENTIFIED));
        verify(bedrock, never()).completeJson(anyString(), any(), anyInt());
    }

    /**
     * Scenario from the review: the patient's client uploaded captions of the caregiver's words
     * and vice versa. Captions carry the uploader, so if they were used the caregiver's question
     * would be tagged [PATIENT]. Only KVS lines, attributed by stream, may reach the model.
     */
    @Test
    void analyze_bothClientsUploadBothSpeakers_onlyKvsAttributionIsUsed() throws Exception {
        // Arrange: each sentence exists as a KVS line and as a caption from each client.
        when(bedrock.anonymizeForPrompt(anyString())).thenAnswer(inv -> inv.getArgument(0));
        when(bedrock.completeJson(anyString(), eq(null), anyInt())).thenReturn(VALID_REPLY);
        transcriptReady(List.of(
                caption(PATIENT_USER_ID, 0L, "Are you having flashbacks?"),
                caption(CAREGIVER_USER_ID, 0L, "Are you having flashbacks?"),
                kvs(CAREGIVER_USER_ID, 0L, "Are you having flashbacks?"),
                caption(PATIENT_USER_ID, 2_000L, "Yes, almost every night."),
                caption(CAREGIVER_USER_ID, 2_000L, "Yes, almost every night."),
                kvs(PATIENT_USER_ID, 2_000L, "Yes, almost every night.")));

        // Act
        adapter.analyze(freshContext());

        // Assert: each sentence once, tagged by its stream.
        final ArgumentCaptor<String> raw = ArgumentCaptor.forClass(String.class);
        verify(bedrock).anonymizeForPrompt(raw.capture());
        assertThat(raw.getValue()).isEqualTo(
                "[CARE_TEAM] Are you having flashbacks?\n"
                        + "[PATIENT] Yes, almost every night.\n");
    }

    /** Captions alone never identify the speaker, even when the patient's client uploaded them. */
    @Test
    void analyze_captionsOnly_skipsAsPatientSpeakerUnidentified() throws Exception {
        transcriptReady(List.of(
                caption(PATIENT_USER_ID, 0L, "How have you been sleeping?"),
                caption(PATIENT_USER_ID, 2_000L, "Not well.")));

        assertThat(adapter.analyze(freshContext()))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.PATIENT_SPEAKER_UNIDENTIFIED));
        verify(bedrock, never()).completeJson(anyString(), any(), anyInt());
    }

    /** The caregiver's stream failed to transcribe: the patient's side alone is still screened. */
    @Test
    void analyze_patientKvsOnly_isScreened() throws Exception {
        when(bedrock.anonymizeForPrompt(anyString())).thenAnswer(inv -> inv.getArgument(0));
        when(bedrock.completeJson(anyString(), eq(null), anyInt())).thenReturn(VALID_REPLY);
        transcriptReady(List.of(kvs(PATIENT_USER_ID, 0L, "I keep reliving it.")));

        assertThat(adapter.analyze(freshContext())).isInstanceOf(AdapterOutcome.Completed.class);
        verify(bedrock).anonymizeForPrompt("[PATIENT] I keep reliving it.\n");
    }

    /** A re-run transcription can store the same KVS segment twice; it is sent once. */
    @Test
    void analyze_duplicateKvsSegments_areSentOnce() throws Exception {
        when(bedrock.anonymizeForPrompt(anyString())).thenAnswer(inv -> inv.getArgument(0));
        when(bedrock.completeJson(anyString(), eq(null), anyInt())).thenReturn(VALID_REPLY);
        transcriptReady(List.of(
                kvs(PATIENT_USER_ID, 0L, "I keep reliving it."),
                kvs(PATIENT_USER_ID, 0L, "I keep reliving it.")));

        adapter.analyze(freshContext());

        verify(bedrock).anonymizeForPrompt("[PATIENT] I keep reliving it.\n");
    }

    /** Happy path: role tags replace speakers, blank lines drop, lines follow conversation time, only anonymized text reaches the prompt, levels map case-insensitively, one Bedrock call. */
    @Test
    void analyze_sendsAnonymizedRoleTaggedTranscriptAndMapsFindings() throws Exception {
        // Arrange — listed out of time order; the whitespace-only patient line must be dropped.
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("COMPLETE");
        when(transcriptService.getSegmentsForCall(CALL_ID)).thenReturn(List.of(
                kvs(PATIENT_USER_ID, 2_000L, "I keep having nightmares about the accident."),
                kvs(CAREGIVER_USER_ID, 0L, "How have you been sleeping?"),
                kvs(PATIENT_USER_ID, 4_000L, "   ")));
        when(bedrock.anonymizeForPrompt(anyString())).thenReturn("ANONYMIZED TRANSCRIPT\n");
        when(bedrock.completeJson(anyString(), eq(null), eq(BedrockTranscriptScreeningAdapter.MAX_OUTPUT_TOKENS)))
                .thenReturn(VALID_REPLY);

        // Act
        final AdapterOutcome outcome = adapter.analyze(freshContext());

        // Assert
        final ArgumentCaptor<String> raw = ArgumentCaptor.forClass(String.class);
        verify(bedrock).anonymizeForPrompt(raw.capture());
        assertThat(raw.getValue()).isEqualTo(
                "[CARE_TEAM] How have you been sleeping?\n"
                        + "[PATIENT] I keep having nightmares about the accident.\n");
        final ArgumentCaptor<String> prompt = ArgumentCaptor.forClass(String.class);
        verify(bedrock).completeJson(prompt.capture(), eq(null), anyInt());
        assertThat(prompt.getValue())
                .contains("<transcript>\nANONYMIZED TRANSCRIPT\n</transcript>")
                .doesNotContain("nightmares about the accident");

        assertThat(outcome).isInstanceOf(AdapterOutcome.Completed.class);
        final List<ConditionFinding> findings = ((AdapterOutcome.Completed) outcome).findings();
        assertThat(findings).containsExactly(
                new ConditionFinding(ConditionName.PTSD, 2, "MODERATE", null, "Describes recurring nightmares."),
                new ConditionFinding(ConditionName.BIPOLAR, 0, "NONE", null, "No relevant statements."));
    }

    /** No JSON object or no conditions array is a retryable failure, never an empty result. */
    @Test
    void parseFindings_rejectsMissingJson() {
        assertThatThrownBy(() -> adapter.parseFindings("")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> adapter.parseFindings("{\"other\":1}")).isInstanceOf(IllegalStateException.class);
    }

    /** A level outside the allowlist is rejected rather than coerced. */
    @Test
    void parseFindings_rejectsUnknownLevel() {
        assertThatThrownBy(() -> adapter.parseFindings("""
                {"conditions":[{"condition":"PTSD","indicator_level":"EXTREME"},
                {"condition":"BIPOLAR","indicator_level":"NONE"}]}"""))
                .isInstanceOf(IllegalStateException.class);
    }

    /** Both requested conditions must be present. */
    @Test
    void parseFindings_rejectsMissingCondition() {
        assertThatThrownBy(() -> adapter.parseFindings("""
                {"conditions":[{"condition":"PTSD","indicator_level":"LOW"}]}"""))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("BIPOLAR");
    }

    /** Extra conditions are ignored; 400-char evidence is cut to the 240 limit; blank evidence becomes null. */
    @Test
    void parseFindings_ignoresUnrequestedConditionsAndTruncatesEvidence() throws Exception {
        final String longEvidence = "x".repeat(400);
        final List<ConditionFinding> findings = adapter.parseFindings("""
                {"conditions":[{"condition":"SCHIZOPHRENIA","indicator_level":"HIGH"},
                {"condition":"ptsd","indicator_level":"HIGH","evidence_summary":"%s"},
                {"condition":"BIPOLAR","indicator_level":"LOW","evidence_summary":""}]}"""
                .formatted(longEvidence));

        assertThat(findings).hasSize(2);
        assertThat(findings.get(0).severityLevel()).isEqualTo(3);
        assertThat(findings.get(0).evidenceSummary()).hasSize(BedrockTranscriptScreeningAdapter.MAX_EVIDENCE_CHARS);
        assertThat(findings.get(1).evidenceSummary()).isNull();
    }

    /** {@code n} distinct 1,000-char lines from {@code speaker}, 1 s apart from {@code firstMs}. */
    private static List<CallTranscriptSegment> lines(final Long speaker, final int n, final long firstMs) {
        return java.util.stream.IntStream.range(0, n)
                .mapToObj(i -> kvs(speaker, firstMs + i * 1_000L, ("line" + i + " ").repeat(200).substring(0, 1000)))
                .toList();
    }

    /** 300 one-thousand-char lines (~300k chars) split into chunks that each fit the budget. */
    @Test
    void buildChunks_everyChunkFitsBudget() {
        final List<String> chunks = BedrockTranscriptScreeningAdapter.buildChunks(
                lines(PATIENT_USER_ID, 300, 0L), PATIENT_USER_ID);

        assertThat(chunks).hasSizeGreaterThan(1)
                .allSatisfy(chunk -> assertThat(chunk)
                        .hasSizeLessThanOrEqualTo(BedrockTranscriptScreeningAdapter.MAX_TRANSCRIPT_CHARS));
    }

    /**
     * The original bug: care-team text filled the whole budget before the patient's first line,
     * which was then dropped while the transcript still counted as "patient spoke". Now the
     * care-team-only chunk is not sent, and the chunk holding the patient's line is.
     */
    @Test
    void buildChunks_careTeamFillsFirstBudget_patientChunkStillSent() {
        // Arrange: 130 care-team lines (~131k chars) overflow one chunk before the patient speaks.
        final List<CallTranscriptSegment> segments = new java.util.ArrayList<>(lines(CAREGIVER_USER_ID, 130, 0L));
        segments.add(kvs(PATIENT_USER_ID, 200_000L, "It started after the accident."));

        // Act
        final List<String> chunks = BedrockTranscriptScreeningAdapter.buildChunks(segments, PATIENT_USER_ID);

        // Assert
        assertThat(chunks).hasSize(1);
        assertThat(chunks.get(0)).contains("[PATIENT] It started after the accident.")
                .contains("[CARE_TEAM]");
    }

    /** Care-team lines only: nothing to screen. */
    @Test
    void buildChunks_careTeamOnly_isEmpty() {
        assertThat(BedrockTranscriptScreeningAdapter.buildChunks(
                lines(CAREGIVER_USER_ID, 3, 0L), PATIENT_USER_ID)).isEmpty();
    }

    /**
     * A disclosure late in a call longer than one budget is screened in a second Bedrock call,
     * and the run keeps the more severe level per condition (PTSD HIGH from the second chunk,
     * BIPOLAR LOW from the first).
     */
    @Test
    void analyze_lateDisclosurePastBudget_screensEveryChunkAndKeepsHighestLevel() throws Exception {
        // Arrange: ~130k chars of patient speech, so the late line lands in chunk two.
        final List<CallTranscriptSegment> segments = new java.util.ArrayList<>(lines(PATIENT_USER_ID, 130, 0L));
        segments.add(kvs(PATIENT_USER_ID, 500_000L, "I still see it every time I close my eyes."));
        transcriptReady(segments);
        when(bedrock.anonymizeForPrompt(anyString())).thenAnswer(inv -> inv.getArgument(0));
        when(bedrock.completeJson(anyString(), eq(null), anyInt())).thenReturn("""
                {"conditions":[{"condition":"PTSD","indicator_level":"LOW","evidence_summary":"early"},
                {"condition":"BIPOLAR","indicator_level":"LOW","evidence_summary":"early"}]}""", """
                {"conditions":[{"condition":"PTSD","indicator_level":"HIGH","evidence_summary":"late"},
                {"condition":"BIPOLAR","indicator_level":"NONE","evidence_summary":"late"}]}""");

        // Act
        final AdapterOutcome outcome = adapter.analyze(freshContext());

        // Assert
        verify(bedrock, org.mockito.Mockito.times(2)).completeJson(anyString(), eq(null), anyInt());
        assertThat(((AdapterOutcome.Completed) outcome).findings()).containsExactly(
                new ConditionFinding(ConditionName.PTSD, 3, "HIGH", null, "late"),
                new ConditionFinding(ConditionName.BIPOLAR, 1, "LOW", null, "early"));
    }
}
