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
 * Validates the Phase 2 transcript screening adapter: waiting for transcription, refusing to
 * screen when no line is attributed to the patient, sending only an anonymized role-tagged
 * transcript, and strictly validating the model's JSON. Bedrock, the transcript store and the
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

    private static CallTranscriptSegment segment(final Long actorUserId, final String text) {
        final CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setActorUserId(actorUserId);
        segment.setText(text);
        return segment;
    }

    /** Registry metadata: id, conditions, and a config version that records model plus prompt version. */
    @Test
    void identity_describesTranscriptModelForPtsdAndBipolar() {
        when(bedrock.resolveTextModelId(null)).thenReturn("amazon.nova-lite-v1:0");

        assertThat(adapter.modelId()).isEqualTo(BedrockTranscriptScreeningAdapter.MODEL_ID);
        assertThat(adapter.supportedConditions()).containsExactlyInAnyOrder(ConditionName.PTSD, ConditionName.BIPOLAR);
        assertThat(adapter.configVersion()).isEqualTo("amazon.nova-lite-v1:0:condition-screen-v1");
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

    /** Mixed-recording or caregiver-only lines cannot be attributed to the patient, so Bedrock is never called. */
    @Test
    void analyze_skipsWhenNoLineIsAttributedToThePatient() throws Exception {
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("COMPLETE");
        when(transcriptService.getSegmentsForCall(CALL_ID)).thenReturn(List.of(
                segment(null, "Mixed-recording line with no attendee"),
                segment(CAREGIVER_USER_ID, "How have you been sleeping?")));

        assertThat(adapter.analyze(freshContext()))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.PATIENT_SPEAKER_UNIDENTIFIED));
        verify(bedrock, never()).completeJson(anyString(), any(), anyInt());
    }

    /** Happy path: role tags replace speakers, blank lines drop, only anonymized text reaches the prompt, levels map case-insensitively. */
    @Test
    void analyze_sendsAnonymizedRoleTaggedTranscriptAndMapsFindings() throws Exception {
        // Arrange — the whitespace-only patient line must be dropped, not sent.
        when(bedrock.canInvokeBedrock()).thenReturn(true);
        transcriptionStatus("COMPLETE");
        when(transcriptService.getSegmentsForCall(CALL_ID)).thenReturn(List.of(
                segment(CAREGIVER_USER_ID, "How have you been sleeping?"),
                segment(PATIENT_USER_ID, "I keep having nightmares about the accident."),
                segment(PATIENT_USER_ID, "   ")));
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

    /** Forty 1,000-char lines exceed the 16,000-char budget the summary pipeline also uses. */
    @Test
    void buildTranscript_capsLengthAtSummaryBudget() {
        final String line = "y".repeat(1000);
        final List<CallTranscriptSegment> segments = java.util.stream.IntStream.range(0, 40)
                .mapToObj(i -> segment(PATIENT_USER_ID, line))
                .toList();

        assertThat(BedrockTranscriptScreeningAdapter.buildTranscript(segments, PATIENT_USER_ID))
                .hasSizeLessThanOrEqualTo(BedrockTranscriptScreeningAdapter.MAX_TRANSCRIPT_CHARS);
    }
}
