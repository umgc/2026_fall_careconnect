package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallRecording;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.PostCallTranscriptionJob;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.PostCallTranscriptionJobRepository;
import com.careconnect.service.CallTranscriptService.TranscriptSegmentInput;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.slf4j.LoggerFactory;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectsRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.services.transcribe.TranscribeClient;
import software.amazon.awssdk.services.transcribe.model.ConflictException;
import software.amazon.awssdk.services.transcribe.model.GetTranscriptionJobRequest;
import software.amazon.awssdk.services.transcribe.model.GetTranscriptionJobResponse;
import software.amazon.awssdk.services.transcribe.model.StartTranscriptionJobRequest;
import software.amazon.awssdk.services.transcribe.model.TranscriptionJob;
import software.amazon.awssdk.services.transcribe.model.TranscriptionJobStatus;

/**
 * Covers the durable job worker (claim / complete / fail), the KVS-per-attendee and mixed-MP4
 * transcription branches, transcript parsing edge cases and S3 cleanup failures of {@link
 * PostCallTranscriptionService}. Transcribe and S3 are Mockito mocks; Transcribe jobs are always
 * reported COMPLETED or FAILED so no poll sleeps occur.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("PostCallTranscriptionService worker and branch tests")
class PostCallTranscriptionServiceWorkerTest {

    private static final String CALL_ID = "call/worker 1";
    private static final String BUCKET = "careconnect-recordings-test";
    private static final String PREFIX = "recordings/call-worker-1/20261001-100000/";
    private static final String PLAYABLE_KEY = PREFIX + "concatenated/composited-video/final.mp4";
    private static final String STREAM_ARN = "arn:aws:kinesisvideo:us-east-1:1:stream/s/1";

    @Mock private TranscribeClient transcribeClient;
    @Mock private S3Client s3Client;
    @Mock private CallTranscriptService callTranscriptService;
    @Mock private CallTelemetryService callTelemetryService;
    @Mock private CallRecordingRepository recordingRepository;
    @Mock private PostCallTranscriptionJobRepository jobRepository;
    @Mock private CallSummaryService callSummaryService;
    @Mock private CallAttendeeRepository callAttendeeRepository;
    @Mock private KvsArchivedMediaExportService kvsArchivedMediaExportService;
    @Mock private KvsAudioTranscodeService kvsAudioTranscodeService;

    private PostCallTranscriptionService service;

    private final Logger serviceLogger =
            (Logger) LoggerFactory.getLogger(PostCallTranscriptionService.class);
    private Level originalLevel;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.TRACE);
        service = new PostCallTranscriptionService();
        ReflectionTestUtils.setField(service, "transcribeClient", transcribeClient);
        ReflectionTestUtils.setField(service, "s3Client", s3Client);
        ReflectionTestUtils.setField(service, "callTranscriptService", callTranscriptService);
        ReflectionTestUtils.setField(service, "callTelemetryService", callTelemetryService);
        ReflectionTestUtils.setField(service, "recordingRepository", recordingRepository);
        ReflectionTestUtils.setField(service, "jobRepository", jobRepository);
        ReflectionTestUtils.setField(service, "callSummaryService", callSummaryService);
        ReflectionTestUtils.setField(service, "callAttendeeRepository", callAttendeeRepository);
        ReflectionTestUtils.setField(service, "kvsArchivedMediaExportService", kvsArchivedMediaExportService);
        ReflectionTestUtils.setField(service, "kvsAudioTranscodeService", kvsAudioTranscodeService);

        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                .thenReturn(ListObjectsV2Response.builder().isTruncated(false).build());
        when(callAttendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of());
        when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of());
    }

    @AfterEach
    void restoreLogger() {
        serviceLogger.setLevel(originalLevel);
    }

    private static CallRecording recording() {
        final CallRecording recording = new CallRecording();
        recording.setId(1L);
        recording.setCallId(CALL_ID);
        recording.setGeneration(2L);
        recording.setS3Bucket(BUCKET);
        recording.setS3Prefix(PREFIX);
        recording.setStartedAt(LocalDateTime.of(2026, 10, 1, 10, 0));
        recording.setEndedAt(LocalDateTime.of(2026, 10, 1, 10, 5));
        return recording;
    }

    private static CallAttendee attendee(final long id, final String chimeId, final String role) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setId(id);
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(chimeId);
        attendee.setKvsStreamArn(STREAM_ARN + id);
        attendee.setUserId(100L + id);
        attendee.setRole(role);
        return attendee;
    }

    private static GetTranscriptionJobResponse job(final TranscriptionJobStatus status) {
        return GetTranscriptionJobResponse.builder()
                .transcriptionJob(
                        TranscriptionJob.builder()
                                .transcriptionJobStatus(status)
                                .failureReason("bad media")
                                .build())
                .build();
    }

    private static ResponseInputStream<GetObjectResponse> json(final String body) {
        return new ResponseInputStream<>(
                GetObjectResponse.builder().build(),
                AbortableInputStream.create(new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8))));
    }

    private void execute(final CallRecording rec) {
        ReflectionTestUtils.invokeMethod(service, "executeTranscription", CALL_ID, rec, PLAYABLE_KEY);
    }

    private static PostCallTranscriptionJob jobRow(final int attempts) {
        final PostCallTranscriptionJob job = new PostCallTranscriptionJob();
        job.setId(5L);
        job.setRecordingId(1L);
        job.setCallId(CALL_ID);
        job.setMediaKey(PLAYABLE_KEY);
        job.setAttemptCount(attempts);
        return job;
    }

    @Nested
    @DisplayName("job enqueue and worker")
    class Worker {

        @Test
        @DisplayName("enqueue ignores incomplete input and recordings that already have a job")
        void enqueueGuards() {
            final CallRecording rec = recording();
            service.transcribeAndCleanup(null, rec, PLAYABLE_KEY);
            service.transcribeAndCleanup(CALL_ID, null, PLAYABLE_KEY);
            service.transcribeAndCleanup(CALL_ID, rec, " ");
            service.transcribeAndCleanup(CALL_ID, rec, null);
            final CallRecording noId = recording();
            noId.setId(null);
            service.transcribeAndCleanup(CALL_ID, noId, PLAYABLE_KEY);
            final CallRecording noBucket = recording();
            noBucket.setS3Bucket(null);
            service.transcribeAndCleanup(CALL_ID, noBucket, PLAYABLE_KEY);
            verifyNoInteractions(jobRepository);

            when(jobRepository.findByRecordingId(1L)).thenReturn(Optional.of(jobRow(0)));
            service.transcribeAndCleanup(CALL_ID, rec, PLAYABLE_KEY);
            verify(jobRepository, never()).save(any(PostCallTranscriptionJob.class));
        }

        @Test
        @DisplayName("startup drain processes due ids and skips jobs another worker claimed")
        void startupDrain_skipsUnclaimed() {
            when(jobRepository.findDueIds()).thenReturn(List.of(5L));
            when(jobRepository.claim(eq(5L), any(UUID.class), eq(1200L))).thenReturn(0);

            service.processDueJobsOnStartup();

            verify(jobRepository).claim(eq(5L), any(UUID.class), eq(1200L));
            verify(jobRepository, never()).findByIdAndClaimToken(anyLong(), any(UUID.class));
        }

        @Test
        @DisplayName("claim returns null when the claimed row cannot be re-read")
        void claim_rowMissing() {
            when(jobRepository.claim(eq(5L), any(UUID.class), anyLong())).thenReturn(1);
            when(jobRepository.findByIdAndClaimToken(eq(5L), any(UUID.class))).thenReturn(Optional.empty());

            assertThat(service.claimTranscriptionWork(5L, UUID.randomUUID())).isNull();
        }

        @Test
        @DisplayName("claim terminates a job whose recording metadata is gone")
        void claim_recordingMissing_terminates() {
            final UUID token = UUID.randomUUID();
            when(jobRepository.claim(5L, token, 1200L)).thenReturn(1);
            when(jobRepository.findByIdAndClaimToken(5L, token)).thenReturn(Optional.of(jobRow(0)));
            when(recordingRepository.findById(1L)).thenReturn(Optional.empty());

            assertThat(service.claimTranscriptionWork(5L, token)).isNull();
            verify(jobRepository).release(eq(5L), eq(token), eq("TERMINAL"), eq(0L), anyString());
        }

        @Test
        @DisplayName("a claimed job without AWS clients is released as retryable")
        void processJob_noAws_failsRetryable() {
            ReflectionTestUtils.setField(service, "transcribeClient", null);
            final PostCallTranscriptionJob row = jobRow(2);
            when(jobRepository.claim(eq(5L), any(UUID.class), anyLong())).thenReturn(1);
            when(jobRepository.findByIdAndClaimToken(eq(5L), any(UUID.class))).thenReturn(Optional.of(row));
            final CallRecording rec = recording();
            rec.setErrorMessage("stitch failed");
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));

            service.processJob(5L);

            assertThat(row.getState()).isEqualTo("RUNNING");
            verify(jobRepository).release(eq(5L), any(UUID.class), eq("RETRYABLE"), eq(60L), eq("stitch failed"));
        }

        @Test
        @DisplayName("a crash after transcription is released terminally once attempts are exhausted")
        void processJob_crash_failsTerminal() {
            final PostCallTranscriptionJob row = jobRow(8);
            when(jobRepository.claim(eq(5L), any(UUID.class), anyLong())).thenReturn(1);
            when(jobRepository.findByIdAndClaimToken(eq(5L), any(UUID.class))).thenReturn(Optional.of(row));
            final CallRecording rec = recording();
            ReflectionTestUtils.setField(service, "kvsArchivedMediaExportService", null);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.COMPLETED));
            when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(json("{\"results\":{}}"));
            when(recordingRepository.findById(1L))
                    .thenReturn(Optional.of(rec))
                    .thenThrow(new RuntimeException((String) null));

            service.processJob(5L);

            verify(jobRepository)
                    .release(eq(5L), any(UUID.class), eq("TERMINAL"), eq(0L), eq("Transcription crashed"));
        }

        @Test
        @DisplayName("completing a COMPLETE recording marks the job complete and tolerates summary failure")
        void complete_marksJobAndToleratesSummaryFailure() {
            final UUID token = UUID.randomUUID();
            final CallRecording rec = recording();
            rec.setTranscriptionStatus(PostCallTranscriptionService.TRANSCRIPTION_STATUS_COMPLETE);
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));
            final PostCallTranscriptionJob row = jobRow(1);
            when(jobRepository.findByIdAndClaimToken(5L, token)).thenReturn(Optional.of(row));
            when(callTelemetryService.getLatestSentimentByChannel(CALL_ID)).thenReturn(Map.of());
            when(callSummaryService.generateAndStoreSummary(eq(CALL_ID), isNull(), any()))
                    .thenThrow(new RuntimeException("bedrock down"));

            service.completeTranscriptionWork(5L, token, 1L, 1);

            assertThat(row.getState()).isEqualTo("COMPLETE");
            assertThat(row.getCompletedAt()).isNotNull();
            verify(jobRepository).save(row);
        }

        @Test
        @DisplayName("completing returns quietly when the claimed job row is gone")
        void complete_jobGone() {
            final UUID token = UUID.randomUUID();
            final CallRecording rec = recording();
            rec.setTranscriptionStatus(PostCallTranscriptionService.TRANSCRIPTION_STATUS_COMPLETE);
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));
            when(jobRepository.findByIdAndClaimToken(5L, token)).thenReturn(Optional.empty());

            service.completeTranscriptionWork(5L, token, 1L, 1);

            verify(jobRepository, never()).save(any(PostCallTranscriptionJob.class));
            verify(jobRepository, never()).release(anyLong(), any(), anyString(), anyLong(), anyString());
        }

        @Test
        @DisplayName("completing a missing recording fails the work with a default message")
        void complete_recordingMissing_fails() {
            final UUID token = UUID.randomUUID();
            when(recordingRepository.findById(1L)).thenReturn(Optional.empty());

            service.completeTranscriptionWork(5L, token, 1L, 0);

            verify(jobRepository)
                    .release(5L, token, "RETRYABLE", 60L, "Transcription has not completed");
        }
    }

    @Nested
    @DisplayName("executeTranscription")
    class Execute {

        @Test
        @DisplayName("returns without work for a null recording")
        void nullRecording_noop() {
            ReflectionTestUtils.invokeMethod(service, "executeTranscription", CALL_ID, null, PLAYABLE_KEY);
            verifyNoInteractions(recordingRepository);
        }

        @Test
        @DisplayName("without KVS services a failed MP4 job marks transcription FAILED")
        void noKvs_mp4Failed() {
            ReflectionTestUtils.setField(service, "kvsAudioTranscodeService", null);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.FAILED));
            final CallRecording rec = recording();

            execute(rec);

            assertThat(rec.getTranscriptionStatus()).isEqualTo("FAILED");
        }

        @Test
        @DisplayName("an invalid recording window falls back to MP4 and an existing job is resumed")
        void invalidWindow_resumesExistingMp4Job() {
            final CallRecording rec = recording();
            rec.setEndedAt(null);
            rec.setInitiatedByUserId(9L);
            when(transcribeClient.startTranscriptionJob(any(StartTranscriptionJobRequest.class)))
                    .thenThrow(ConflictException.builder().message("exists").build());
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.COMPLETED));
            when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(json("{\"results\":{\"items\":[]}}"));
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));

            execute(rec);

            assertThat(rec.getTranscriptionStatus()).isEqualTo("COMPLETE");
            verify(s3Client, never()).deleteObject(any(DeleteObjectRequest.class));
        }

        @Test
        @DisplayName("a mixed-MP4 start failure marks transcription FAILED")
        void mp4StartFailure_marksFailed() {
            when(transcribeClient.startTranscriptionJob(any(StartTranscriptionJobRequest.class)))
                    .thenThrow(new RuntimeException("limit exceeded"));
            final CallRecording rec = recording();

            execute(rec);

            assertThat(rec.getTranscriptionStatus()).isEqualTo("FAILED");
        }

        @Test
        @DisplayName("empty per-attendee transcripts fall back to MP4 diarization with speaker changes")
        void emptyAttendeeTranscripts_fallBackToMp4() throws Exception {
            final CallAttendee caregiver = attendee(1L, "att-1", "CAREGIVER");
            final CallAttendee noRole = attendee(2L, null, " ");
            final CallAttendee unmapped = attendee(3L, "att-3", "PATIENT");
            unmapped.setKvsStreamArn(" ");
            when(callAttendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(caregiver, noRole, unmapped));
            // Each attendee gets its own temp files; the service deletes them after every attendee.
            when(kvsArchivedMediaExportService.exportAttendeeRange(anyString(), any(Instant.class), any(Instant.class)))
                    .thenAnswer(inv -> Files.createTempFile("kvs-worker", ".mkv"));
            when(kvsAudioTranscodeService.toWav(any(Path.class)))
                    .thenAnswer(inv -> Files.createTempFile("kvs-worker", ".wav"));
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.COMPLETED));
            final String empty = "{\"results\":{\"audio_segments\":[],\"items\":[]}}";
            final String mixed =
                    """
                    {"results":{"items":[
                      {"type":"punctuation","alternatives":[{"content":","}]},
                      {"type":"pronunciation","start_time":"0.0","end_time":"0.1","alternatives":[{"content":"um"}]},
                      {"type":"pronunciation","speaker_label":"spk_0","start_time":"0.1","end_time":"0.4","alternatives":[{"content":"hello"}]},
                      {"type":"pronunciation","start_time":"","end_time":"bad","alternatives":[{"content":"there"}]},
                      {"type":"pronunciation","speaker_label":"spk_9","start_time":"1.0","end_time":"1.3","alternatives":[{"content":"noise"}]},
                      {"type":"punctuation","alternatives":[{"content":"."}]},
                      {"type":"pronunciation","speaker_label":"spk_1","start_time":"2.0","end_time":"2.5","alternatives":[{"content":"bye"}]}
                    ]}}
                    """;
            when(s3Client.getObject(any(GetObjectRequest.class)))
                    .thenReturn(json(empty))
                    .thenReturn(json(empty))
                    .thenReturn(json(mixed));
            final CallTelemetryEvent join = new CallTelemetryEvent();
            join.setEventType("CALL_JOIN");
            join.setActorUserId(101L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(join));
            final CallRecording rec = recording();
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));
            when(callTranscriptService.recordSegments(eq(CALL_ID), isNull(), org.mockito.ArgumentMatchers.<List<TranscriptSegmentInput>>any()))
                    .thenReturn(3);

            execute(rec);

            @SuppressWarnings("unchecked")
            final ArgumentCaptor<List<TranscriptSegmentInput>> captor = ArgumentCaptor.forClass(List.class);
            verify(callTranscriptService).recordSegments(eq(CALL_ID), isNull(), captor.capture());
            assertThat(captor.getValue())
                    .extracting(TranscriptSegmentInput::speakerLabel)
                    .containsExactly("Speaker 1", "Unidentified Speaker", "Speaker 2");
            assertThat(captor.getValue().get(0).text()).isEqualTo("hello there");
            assertThat(rec.getTranscriptionStatus()).isEqualTo("COMPLETE");
            final ArgumentCaptor<PutObjectRequest> put = ArgumentCaptor.forClass(PutObjectRequest.class);
            verify(s3Client, times(2)).putObject(put.capture(), any(RequestBody.class));
            assertThat(put.getAllValues().get(1).key()).endsWith("speaker-id/audio/unknown.wav");
            verify(s3Client, times(2)).deleteObject(any(DeleteObjectRequest.class));
        }

        @Test
        @DisplayName("an attendee job that fails or an export error falls back to MP4")
        void attendeeFailure_fallsBackToMp4() throws Exception {
            when(callAttendeeRepository.findByCallId(CALL_ID))
                    .thenReturn(List.of(attendee(1L, "att-1", "CAREGIVER")));
            final Path rawDir = Files.createTempDirectory("kvs-worker-dir");
            final Path child = Files.createTempFile(rawDir, "child", ".bin");
            final Path wav = Files.createTempFile("kvs-worker", ".wav");
            when(kvsArchivedMediaExportService.exportAttendeeRange(anyString(), any(Instant.class), any(Instant.class)))
                    .thenReturn(rawDir)
                    .thenThrow(new IllegalStateException("No KVS fragments found"));
            when(kvsAudioTranscodeService.toWav(rawDir)).thenReturn(wav);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.FAILED));
            final CallRecording rec = recording();

            try {
                execute(rec);
                execute(rec);
            } finally {
                Files.deleteIfExists(child);
                Files.deleteIfExists(rawDir);
            }

            assertThat(rec.getTranscriptionStatus()).isEqualTo("FAILED");
            verify(kvsArchivedMediaExportService, times(2))
                    .exportAttendeeRange(anyString(), any(Instant.class), any(Instant.class));
        }

        @Test
        @DisplayName("item-based attendee transcripts split utterances on long pauses")
        void attendeeItems_splitOnPauses() throws Exception {
            when(callAttendeeRepository.findByCallId(CALL_ID))
                    .thenReturn(List.of(attendee(1L, "att-1", "PATIENT")));
            final Path raw = Files.createTempFile("kvs-worker", ".mkv");
            final Path wav = Files.createTempFile("kvs-worker", ".wav");
            when(kvsArchivedMediaExportService.exportAttendeeRange(anyString(), any(Instant.class), any(Instant.class)))
                    .thenReturn(raw);
            when(kvsAudioTranscodeService.toWav(raw)).thenReturn(wav);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.COMPLETED));
            final String items =
                    """
                    {"results":{"audio_segments":[{"transcript":" ","start_time":"0","end_time":"1"}],"items":[
                      {"type":"punctuation","alternatives":[{"content":","}]},
                      {"type":"pronunciation","start_time":"0.0","end_time":"0.3","alternatives":[{"content":"good"}]},
                      {"type":"pronunciation","start_time":"0.4","end_time":"0.6","alternatives":[{"content":"morning"}]},
                      {"type":"punctuation","alternatives":[{"content":"."}]},
                      {"type":"pronunciation","alternatives":[{"content":""}]},
                      {"type":"pronunciation","start_time":"3.0","end_time":"3.4","alternatives":[{"content":"thanks"}]}
                    ]}}
                    """;
            when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(json(items));
            when(callTranscriptService.recordSegments(eq(CALL_ID), eq(101L), org.mockito.ArgumentMatchers.<List<TranscriptSegmentInput>>any()))
                    .thenReturn(2);
            final CallRecording rec = recording();
            rec.setInitiatedByUserId(9L);
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));

            execute(rec);

            @SuppressWarnings("unchecked")
            final ArgumentCaptor<List<TranscriptSegmentInput>> captor = ArgumentCaptor.forClass(List.class);
            verify(callTranscriptService).recordSegments(eq(CALL_ID), eq(101L), captor.capture());
            assertThat(captor.getValue())
                    .extracting(TranscriptSegmentInput::text)
                    .containsExactly("good morning.", "thanks");
            assertThat(captor.getValue().get(0).speakerLabel()).isEqualTo("Patient");
            assertThat(rec.getTranscriptionStatus()).isEqualTo("COMPLETE");
        }

        @Test
        @DisplayName("speaker-id cleanup and S3 deletion failures do not change the outcome")
        void cleanupFailures_areTolerated() {
            ReflectionTestUtils.setField(service, "kvsArchivedMediaExportService", null);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.COMPLETED));
            when(s3Client.getObject(any(GetObjectRequest.class))).thenAnswer(inv -> json("{\"results\":{}}"));
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenThrow(new RuntimeException("telemetry down"));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenThrow(new IllegalStateException("client closed"))
                    .thenThrow(new RuntimeException("s3 down"));
            when(s3Client.deleteObject(any(DeleteObjectRequest.class))).thenThrow(new RuntimeException("denied"));
            final CallRecording rec = recording();
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));

            execute(rec);
            execute(rec);

            assertThat(rec.getTranscriptionStatus()).isEqualTo("COMPLETE");
        }

        @Test
        @DisplayName("speaker-id cleanup pages through truncated listings")
        void cleanup_pagesThroughListings() {
            ReflectionTestUtils.setField(service, "kvsArchivedMediaExportService", null);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.FAILED));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(
                            ListObjectsV2Response.builder()
                                    .contents(S3Object.builder().key(PREFIX + "speaker-id/a.wav").build())
                                    .isTruncated(true)
                                    .nextContinuationToken("page-2")
                                    .build())
                    .thenReturn(ListObjectsV2Response.builder().isTruncated(false).build());

            execute(recording());

            final ArgumentCaptor<ListObjectsV2Request> captor = ArgumentCaptor.forClass(ListObjectsV2Request.class);
            verify(s3Client, times(2)).listObjectsV2(captor.capture());
            assertThat(captor.getAllValues().get(1).continuationToken()).isEqualTo("page-2");
            verify(s3Client).deleteObjects(any(DeleteObjectsRequest.class));
        }

        @Test
        @DisplayName("a recording without S3 location skips cleanup and S3 deletion; status save failures are logged")
        void noS3Location_andStatusSaveFailure() {
            ReflectionTestUtils.setField(service, "kvsArchivedMediaExportService", null);
            when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                    .thenReturn(job(TranscriptionJobStatus.COMPLETED));
            when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(json("{\"results\":{}}"));
            final CallRecording rec = recording();
            rec.setS3Bucket(null);
            when(recordingRepository.save(any(CallRecording.class))).thenThrow(new RuntimeException("db down"));
            when(recordingRepository.findById(1L)).thenReturn(Optional.of(rec));

            execute(rec);

            verify(s3Client, never()).listObjectsV2(any(ListObjectsV2Request.class));
            verify(s3Client, never()).deleteObject(any(DeleteObjectRequest.class));
        }
    }
}
