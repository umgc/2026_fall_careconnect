package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallRecording;
import com.careconnect.model.conditiondetection.ConditionDetectionContext;
import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.service.KvsArchivedMediaExportService;
import com.careconnect.service.KvsAudioClip;
import com.careconnect.service.KvsAudioTranscodeService;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
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
 * Unit tests for {@link KintsugiDamAdapter}. KVS export, ffmpeg and the sidecar are mocked
 * because they are network or process boundaries; temp-file cleanup uses real files.
 */
@ExtendWith(MockitoExtension.class)
class KintsugiDamAdapterTest {

    private static final String CALL_ID = "call-1";
    private static final Long PATIENT_USER_ID = 70L;
    private static final Long CAREGIVER_USER_ID = 80L;
    private static final Long RECORDING_ID = 55L;
    private static final String PATIENT_ARN = "arn:patient";
    private static final String OTHER_ARN = "arn:caregiver";

    @Mock
    private DamSidecarClient sidecar;
    @Mock
    private KvsArchivedMediaExportService kvsExport;
    @Mock
    private KvsAudioTranscodeService transcoder;
    @Mock
    private CallRecordingRepository recordingRepository;
    @Mock
    private CallAttendeeRepository attendeeRepository;

    private KintsugiDamAdapter adapter;
    /** Recording started one hour ago (UTC), so it is well inside the 20 hour audio window. */
    private LocalDateTime base;

    @BeforeEach
    void setUp() {
        adapter = new KintsugiDamAdapter(
                sidecar, kvsExport, transcoder, recordingRepository, attendeeRepository, 20L);
        // Sidecar healthy by default; the not-ready path has its own test. Lenient because
        // early-return tests never reach the health check.
        lenient().when(sidecar.isReady()).thenReturn(true);
        base = LocalDateTime.now(ZoneOffset.UTC).minusHours(1).withNano(0);
    }

    private ConditionDetectionContext context(final Long recordingId) {
        return new ConditionDetectionContext(CALL_ID, 7L, PATIENT_USER_ID, recordingId, base);
    }

    private CallRecording recording(final LocalDateTime startedAt, final LocalDateTime endedAt) {
        return ConditionDetectionFixtures.recording(startedAt, endedAt);
    }

    private void stubRecording(final CallRecording recording) {
        when(recordingRepository.findById(RECORDING_ID)).thenReturn(Optional.of(recording));
    }

    private CallAttendee row(
            final long id, final Long userId, final String arn,
            final LocalDateTime joinedAt, final LocalDateTime leftAt) {
        return ConditionDetectionFixtures.attendee(id, userId, arn, joinedAt, leftAt);
    }

    /** Export result for a raw file; the trim window is the transcoder's concern, mocked here. */
    private static KvsAudioClip clip(final Path raw) {
        return new KvsAudioClip(raw, 0L, 60_000L);
    }

    private static DamSidecarClient.DamResult okResult(
            final int depressionLevel, final int anxietyLevel) {
        return new DamSidecarClient.DamResult(
                DamSidecarClient.STATUS_OK, 41.5, "rev",
                new DamSidecarClient.DamScore(0.31, depressionLevel),
                new DamSidecarClient.DamScore(0.77, anxietyLevel));
    }

    // -------------------------------------------------------------- metadata

    /** Scenario: static adapter metadata that is persisted on runs and shown in the UI. */
    @Test
    void metadata_describesPatientAudioModel() {
        assertThat(adapter.modelId()).isEqualTo("kintsugi-dam-3.1");
        assertThat(adapter.inputKind()).isEqualTo(ConditionInputKind.PATIENT_AUDIO);
        assertThat(adapter.supportedConditions())
                .containsExactlyInAnyOrder(ConditionName.DEPRESSION, ConditionName.ANXIETY);
        assertThat(adapter.configVersion()).isEqualTo("dam3.1:published-thresholds-v1");
        assertThat(adapter.displayName()).isNotBlank();
    }

    // -------------------------------------------------------- recording gates

    /** Scenario: enqueue found no recording, so the adapter never touches the repository. */
    @Test
    void analyze_nullRecordingId_isNoRecording() throws Exception {
        assertThat(adapter.analyze(context(null)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING));
        verifyNoInteractions(recordingRepository, kvsExport, transcoder, sidecar);
    }

    /** Scenario: the recording id no longer resolves. */
    @Test
    void analyze_recordingMissing_isNoRecording() throws Exception {
        when(recordingRepository.findById(RECORDING_ID)).thenReturn(Optional.empty());

        assertThat(adapter.analyze(context(RECORDING_ID)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING));
    }

    /** Scenario: a recording that never started has no usable window. */
    @Test
    void analyze_recordingWithoutStart_isNoRecording() throws Exception {
        stubRecording(recording(null, base));

        assertThat(adapter.analyze(context(RECORDING_ID)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING));
    }

    /** Scenario: endedAt is null while the recording finalizes, so wait 60 s without consuming an attempt. */
    @Test
    void analyze_recordingNotEnded_isDeferredSixtySeconds() throws Exception {
        stubRecording(recording(base, null));

        assertThat(adapter.analyze(context(RECORDING_ID)))
                .isEqualTo(new AdapterOutcome.Deferred(60L));
        verifyNoInteractions(kvsExport, transcoder, sidecar);
    }

    /** Scenario: ended 21 h ago against a 20 h limit, so KVS retention may have lapsed. */
    @Test
    void analyze_recordingOlderThanAudioMaxAge_isAudioExpired() throws Exception {
        final LocalDateTime ended = LocalDateTime.now(ZoneOffset.UTC).minusHours(21);
        stubRecording(recording(ended.minusMinutes(10), ended));

        assertThat(adapter.analyze(context(RECORDING_ID)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.AUDIO_EXPIRED));
        verifyNoInteractions(kvsExport, transcoder, sidecar);
    }

    // --------------------------------------------------------- row selection

    /** Scenario: caregiver, blank-ARN and null-ARN rows are ignored; the patient row joined 5 min before the recording and is clamped up to the recording start. */
    @Test
    void analyze_exportsOnlyPatientRowsWithStreamArnClampedToRecording() throws Exception {
        final LocalDateTime started = base;
        final LocalDateTime ended = base.plusMinutes(10);
        stubRecording(recording(started, ended));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                // Caregiver row must be ignored even though it has a stream.
                row(1, CAREGIVER_USER_ID, OTHER_ARN, started, ended),
                // Joined before the recording started, left mid-call: from clamps up to started.
                row(2, PATIENT_USER_ID, PATIENT_ARN, started.minusMinutes(5), started.plusMinutes(3)),
                // Blank ARN and null ARN rows are not exportable.
                row(3, PATIENT_USER_ID, " ", started, ended),
                row(4, PATIENT_USER_ID, null, started, ended)));
        final Path raw = Files.createTempFile("dam-raw", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        try {
            when(kvsExport.exportAttendeeRange(any(), any(), any())).thenReturn(clip(raw));
            when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
            when(sidecar.analyze(wav)).thenReturn(okResult(0, 0));

            adapter.analyze(context(RECORDING_ID));

            verify(kvsExport).exportAttendeeRange(
                    PATIENT_ARN,
                    started.toInstant(ZoneOffset.UTC),
                    started.plusMinutes(3).toInstant(ZoneOffset.UTC));
            verify(kvsExport, never()).exportAttendeeRange(eq(OTHER_ARN), any(), any());
            verify(kvsExport, org.mockito.Mockito.times(1)).exportAttendeeRange(any(), any(), any());
        } finally {
            Files.deleteIfExists(raw);
            Files.deleteIfExists(wav);
        }
    }

    /**
     * Scenario: a null leftAt and a leftAt after the recording end. The open row is ended by the
     * patient's next join (a stale row must not keep reading a possibly reassigned stream); the
     * late leave is clamped to the recording end.
     */
    @Test
    void analyze_openEndedRowAndLateLeave_areClampedToRecordingEnd() throws Exception {
        final LocalDateTime started = base;
        final LocalDateTime ended = base.plusMinutes(10);
        stubRecording(recording(started, ended));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, "arn:open", started.plusMinutes(1), null),
                row(2, PATIENT_USER_ID, "arn:late", started.plusMinutes(2), ended.plusMinutes(30))));
        final Path rawA = Files.createTempFile("dam-raw", ".webm");
        final Path rawB = Files.createTempFile("dam-raw", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        try {
            when(kvsExport.exportAttendeeRange(eq("arn:open"), any(), any())).thenReturn(clip(rawA));
            when(kvsExport.exportAttendeeRange(eq("arn:late"), any(), any())).thenReturn(clip(rawB));
            when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
            when(sidecar.analyze(wav)).thenReturn(okResult(0, 0));

            adapter.analyze(context(RECORDING_ID));

            final Instant endInstant = ended.toInstant(ZoneOffset.UTC);
            verify(kvsExport).exportAttendeeRange(
                    "arn:open",
                    started.plusMinutes(1).toInstant(ZoneOffset.UTC),
                    started.plusMinutes(2).toInstant(ZoneOffset.UTC));
            verify(kvsExport).exportAttendeeRange(
                    "arn:late", started.plusMinutes(2).toInstant(ZoneOffset.UTC), endInstant);
        } finally {
            Files.deleteIfExists(rawA);
            Files.deleteIfExists(rawB);
            Files.deleteIfExists(wav);
        }
    }

    /** Scenario: the sidecar is restarting or still loading, so the run waits without exporting audio or spending an attempt. */
    @Test
    void analyze_sidecarNotReady_defersBeforeExportingAudio() throws Exception {
        // Arrange
        when(recordingRepository.findById(RECORDING_ID))
                .thenReturn(Optional.of(recording(base, base.plusMinutes(5))));
        when(sidecar.isReady()).thenReturn(false);

        // Act
        final AdapterOutcome outcome = adapter.analyze(context(RECORDING_ID));

        // Assert
        assertThat(outcome).isEqualTo(new AdapterOutcome.Deferred(KintsugiDamAdapter.SIDECAR_WAIT_SECONDS));
        verifyNoInteractions(attendeeRepository, kvsExport, transcoder);
        verify(sidecar, never()).analyze(any());
    }

    /** Scenario: rows that left before the recording began, joined after it ended, or have zero length are not exported. */
    @Test
    void analyze_rowWithEmptyWindow_isSkippedWithoutExport() throws Exception {
        final LocalDateTime started = base;
        final LocalDateTime ended = base.plusMinutes(10);
        stubRecording(recording(started, ended));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                // Left before the recording began, and joined after it ended: to <= from.
                row(1, PATIENT_USER_ID, "arn:before", started.minusMinutes(9), started.minusMinutes(2)),
                row(2, PATIENT_USER_ID, "arn:after", ended.plusMinutes(1), null),
                row(3, PATIENT_USER_ID, "arn:zero", started.plusMinutes(4), started.plusMinutes(4))));

        assertThat(adapter.analyze(context(RECORDING_ID)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_PATIENT_AUDIO));

        verifyNoInteractions(kvsExport, transcoder);
        verify(sidecar, never()).analyze(any());
    }

    /** Scenario: a rejoin; rows are deliberately listed out of order and must be concatenated in joinedAt order at DAM's 16 kHz. */
    @Test
    void analyze_twoPatientRows_transcodedTogetherInJoinOrderAt16kHz() throws Exception {
        final LocalDateTime started = base;
        final LocalDateTime ended = base.plusMinutes(10);
        stubRecording(recording(started, ended));
        // Deliberately listed out of order: the later join comes first.
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(2, PATIENT_USER_ID, "arn:second", started.plusMinutes(5), ended),
                row(1, PATIENT_USER_ID, "arn:first", started.plusMinutes(1), started.plusMinutes(3))));
        final Path rawFirst = Files.createTempFile("dam-raw-1", ".webm");
        final Path rawSecond = Files.createTempFile("dam-raw-2", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        try {
            when(kvsExport.exportAttendeeRange(eq("arn:first"), any(), any())).thenReturn(clip(rawFirst));
            when(kvsExport.exportAttendeeRange(eq("arn:second"), any(), any())).thenReturn(clip(rawSecond));
            when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
            when(sidecar.analyze(wav)).thenReturn(okResult(0, 0));

            adapter.analyze(context(RECORDING_ID));

            @SuppressWarnings("unchecked")
            final ArgumentCaptor<List<KvsAudioClip>> clips = ArgumentCaptor.forClass(List.class);
            verify(transcoder).toMonoWav(clips.capture(), eq(16000));
            assertThat(clips.getValue()).extracting(KvsAudioClip::file).containsExactly(rawFirst, rawSecond);
        } finally {
            Files.deleteIfExists(rawFirst);
            Files.deleteIfExists(rawSecond);
            Files.deleteIfExists(wav);
        }
    }

    /**
     * Scenario: a rapid rejoin. The first join's leave (3:30) was recorded after the second join
     * (3:00). Overlapping windows would score the same speech twice, so the second join ends the
     * first window and the second export starts there.
     */
    @Test
    void analyze_overlappingRejoins_exportNonOverlappingWindows() throws Exception {
        // Arrange
        final LocalDateTime started = base;
        final LocalDateTime ended = base.plusMinutes(10);
        stubRecording(recording(started, ended));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, "arn:first", started.plusMinutes(1), started.plusSeconds(210)),
                row(2, PATIENT_USER_ID, "arn:second", started.plusMinutes(3), null)));
        final Path rawFirst = Files.createTempFile("dam-raw-1", ".webm");
        final Path rawSecond = Files.createTempFile("dam-raw-2", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        try {
            when(kvsExport.exportAttendeeRange(eq("arn:first"), any(), any())).thenReturn(clip(rawFirst));
            when(kvsExport.exportAttendeeRange(eq("arn:second"), any(), any())).thenReturn(clip(rawSecond));
            when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
            when(sidecar.analyze(wav)).thenReturn(okResult(0, 0));

            // Act
            adapter.analyze(context(RECORDING_ID));

            // Assert
            verify(kvsExport).exportAttendeeRange("arn:first",
                    started.plusMinutes(1).toInstant(ZoneOffset.UTC),
                    started.plusMinutes(3).toInstant(ZoneOffset.UTC));
            verify(kvsExport).exportAttendeeRange("arn:second",
                    started.plusMinutes(3).toInstant(ZoneOffset.UTC),
                    ended.toInstant(ZoneOffset.UTC));
        } finally {
            Files.deleteIfExists(rawFirst);
            Files.deleteIfExists(rawSecond);
            Files.deleteIfExists(wav);
        }
    }

    /** Scenario: KVS has no fragments for any join, so the run is skipped and ffmpeg is never started. */
    @Test
    void analyze_exportThrowsIllegalStateForEveryRow_isNoPatientAudio() throws Exception {
        stubRecording(recording(base, base.plusMinutes(10)));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, "arn:a", base, base.plusMinutes(2)),
                row(2, PATIENT_USER_ID, "arn:b", base.plusMinutes(3), null)));
        when(kvsExport.exportAttendeeRange(any(), any(), any()))
                .thenThrow(new IllegalStateException("no fragments"));

        assertThat(adapter.analyze(context(RECORDING_ID)))
                .isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_PATIENT_AUDIO));

        verifyNoInteractions(transcoder);
        verify(sidecar, never()).analyze(any());
    }

    /** Scenario: only the second join has audio; it alone is transcoded. */
    @Test
    void analyze_oneRowHasNoAudio_otherRowStillAnalysed() throws Exception {
        stubRecording(recording(base, base.plusMinutes(10)));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, "arn:a", base, base.plusMinutes(2)),
                row(2, PATIENT_USER_ID, "arn:b", base.plusMinutes(3), null)));
        final Path raw = Files.createTempFile("dam-raw", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        try {
            when(kvsExport.exportAttendeeRange(eq("arn:a"), any(), any()))
                    .thenThrow(new IllegalStateException("no fragments"));
            when(kvsExport.exportAttendeeRange(eq("arn:b"), any(), any())).thenReturn(clip(raw));
            when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
            when(sidecar.analyze(wav)).thenReturn(okResult(0, 0));

            assertThat(adapter.analyze(context(RECORDING_ID))).isInstanceOf(AdapterOutcome.Completed.class);
            verify(transcoder).toMonoWav(List.of(clip(raw)), 16000);
        } finally {
            Files.deleteIfExists(raw);
            Files.deleteIfExists(wav);
        }
    }

    /** Scenario: an I/O failure is transient, so it propagates and the run retries. */
    @Test
    void analyze_nonIllegalStateExportFailure_propagatesForRetry() throws Exception {
        stubRecording(recording(base, base.plusMinutes(10)));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, "arn:a", base, null)));
        when(kvsExport.exportAttendeeRange(any(), any(), any()))
                .thenThrow(new java.io.IOException("s3 down"));

        assertThatThrownBy(() -> adapter.analyze(context(RECORDING_ID)))
                .isInstanceOf(java.io.IOException.class);
    }

    // ------------------------------------------------------------ happy path

    /** Scenario: depression level 1 and anxiety level 3 map to their labels, raw scores are kept, and both real temp files are removed. */
    @Test
    void analyze_happyPath_mapsLevelsKeepsRawScoresAndDeletesTempFiles() throws Exception {
        stubRecording(recording(base, base.plusMinutes(10)));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, PATIENT_ARN, base, null)));
        final Path raw = Files.createTempFile("dam-raw", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        when(kvsExport.exportAttendeeRange(any(), any(), any())).thenReturn(clip(raw));
        when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
        when(sidecar.analyze(wav)).thenReturn(okResult(1, 3));

        final AdapterOutcome outcome = adapter.analyze(context(RECORDING_ID));

        assertThat(outcome).isInstanceOf(AdapterOutcome.Completed.class);
        final AdapterOutcome.Completed completed = (AdapterOutcome.Completed) outcome;
        assertThat(completed.speechSeconds()).isEqualTo(41.5);
        assertThat(completed.findings()).containsExactly(
                new ConditionFinding(ConditionName.DEPRESSION, 1, "MILD_TO_MODERATE", 0.31, null),
                new ConditionFinding(ConditionName.ANXIETY, 3, "SEVERE", 0.77, null));
        assertThat(raw).doesNotExist();
        assertThat(wav).doesNotExist();
    }

    /** Scenario: the sidecar is down; PHI audio temp files must still be deleted. */
    @Test
    void analyze_sidecarThrows_stillDeletesTempFilesAndPropagates() throws Exception {
        stubRecording(recording(base, base.plusMinutes(10)));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, PATIENT_ARN, base, null)));
        final Path raw = Files.createTempFile("dam-raw", ".webm");
        final Path wav = Files.createTempFile("dam-wav", ".wav");
        when(kvsExport.exportAttendeeRange(any(), any(), any())).thenReturn(clip(raw));
        when(transcoder.toMonoWav(anyList(), anyInt())).thenReturn(wav);
        when(sidecar.analyze(wav)).thenThrow(new IllegalStateException("sidecar 503"));

        assertThatThrownBy(() -> adapter.analyze(context(RECORDING_ID)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("503");

        assertThat(raw).doesNotExist();
        assertThat(wav).doesNotExist();
    }

    /** Scenario: ffmpeg fails before a WAV exists; the raw export is still deleted. */
    @Test
    void analyze_transcodeThrows_deletesRawFiles() throws Exception {
        stubRecording(recording(base, base.plusMinutes(10)));
        when(attendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(
                row(1, PATIENT_USER_ID, PATIENT_ARN, base, null)));
        final Path raw = Files.createTempFile("dam-raw", ".webm");
        when(kvsExport.exportAttendeeRange(any(), any(), any())).thenReturn(clip(raw));
        when(transcoder.toMonoWav(anyList(), anyInt())).thenThrow(new IllegalStateException("ffmpeg"));

        assertThatThrownBy(() -> adapter.analyze(context(RECORDING_ID)))
                .isInstanceOf(IllegalStateException.class);

        assertThat(raw).doesNotExist();
        verify(sidecar, never()).analyze(any());
    }

    // -------------------------------------------------------------- toOutcome

    /** Scenario: VAD found too little speech (4.5 s). */
    @Test
    void toOutcome_insufficientSpeech_isSkippedWithSpeechSeconds() {
        final AdapterOutcome outcome = KintsugiDamAdapter.toOutcome(new DamSidecarClient.DamResult(
                DamSidecarClient.STATUS_INSUFFICIENT_SPEECH, 4.5, null, null, null));

        assertThat(outcome).isEqualTo(
                new AdapterOutcome.Skipped(ConditionSkipReason.INSUFFICIENT_SPEECH, 4.5));
    }

    /** Scenario: the sidecar rejected the audio as unreadable. */
    @Test
    void toOutcome_invalidAudio_isNoPatientAudio() {
        final AdapterOutcome outcome = KintsugiDamAdapter.toOutcome(new DamSidecarClient.DamResult(
                DamSidecarClient.STATUS_INVALID_AUDIO, null, null, null, null));

        assertThat(outcome).isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_PATIENT_AUDIO));
    }

    /** Scenario: an unrecognized status is a contract violation and should retry rather than guess. */
    @Test
    void toOutcome_unknownStatus_throws() {
        assertThatThrownBy(() -> KintsugiDamAdapter.toOutcome(
                new DamSidecarClient.DamResult("WAT", null, null, null, null)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("WAT");
    }

    /** Scenario: every depression level 0..2 maps to its label. */
    @Test
    void toOutcome_depressionLevelsAcrossFullScale() {
        final String[] labels = {"NONE", "MILD_TO_MODERATE", "SEVERE"};
        for (int level = 0; level < labels.length; level++) {
            final AdapterOutcome.Completed completed = (AdapterOutcome.Completed)
                    KintsugiDamAdapter.toOutcome(okResult(level, 0));
            assertThat(completed.findings().get(0).severityLabel()).isEqualTo(labels[level]);
            assertThat(completed.findings().get(0).severityLevel()).isEqualTo(level);
        }
    }

    /** Scenario: every anxiety level 0..3 maps to its label. */
    @Test
    void toOutcome_anxietyLevelsAcrossFullScale() {
        final String[] labels = {"NONE", "MILD", "MODERATE", "SEVERE"};
        for (int level = 0; level < labels.length; level++) {
            final AdapterOutcome.Completed completed = (AdapterOutcome.Completed)
                    KintsugiDamAdapter.toOutcome(okResult(0, level));
            assertThat(completed.findings().get(1).severityLabel()).isEqualTo(labels[level]);
        }
    }

    /** Scenario: levels just outside each scale (depression 3, anxiety 4), negative, null level and missing score all fail loudly. */
    @Test
    void toOutcome_levelOutOfRangeOrNull_throws() {
        // Depression only has levels 0..2, anxiety 0..3.
        assertThatThrownBy(() -> KintsugiDamAdapter.toOutcome(okResult(3, 0)))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> KintsugiDamAdapter.toOutcome(okResult(-1, 0)))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> KintsugiDamAdapter.toOutcome(okResult(0, 4)))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> KintsugiDamAdapter.toOutcome(new DamSidecarClient.DamResult(
                DamSidecarClient.STATUS_OK, 10.0, null,
                new DamSidecarClient.DamScore(0.1, null),
                new DamSidecarClient.DamScore(0.1, 0))))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> KintsugiDamAdapter.toOutcome(new DamSidecarClient.DamResult(
                DamSidecarClient.STATUS_OK, 10.0, null, null,
                new DamSidecarClient.DamScore(0.1, 0))))
                .isInstanceOf(IllegalStateException.class);
    }
}
