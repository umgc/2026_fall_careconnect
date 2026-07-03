package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallRecording;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.service.CallTranscriptService.TranscriptSegmentInput;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;
import software.amazon.awssdk.services.transcribe.TranscribeClient;
import software.amazon.awssdk.services.transcribe.model.GetTranscriptionJobRequest;
import software.amazon.awssdk.services.transcribe.model.GetTranscriptionJobResponse;
import software.amazon.awssdk.services.transcribe.model.MediaFormat;
import software.amazon.awssdk.services.transcribe.model.StartTranscriptionJobRequest;
import software.amazon.awssdk.services.transcribe.model.StartTranscriptionJobResponse;
import software.amazon.awssdk.services.transcribe.model.TranscriptionJob;
import software.amazon.awssdk.services.transcribe.model.TranscriptionJobStatus;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("PostCallTranscriptionService Tests")
class PostCallTranscriptionServiceTest {

    private static final String CALL_ID = "chime_call_1";
    private static final String BUCKET = "careconnect-recordings-test";
    private static final String PREFIX = "recordings/chime_call_1/20260703-130000/";
    private static final String PLAYABLE_KEY = PREFIX + "concatenated/composited-video/final.mp4";
    private static final String STREAM_ARN =
            "arn:aws:kinesisvideo:us-east-1:123:stream/ChimeMediaPipelines-test/1";

    @Mock private TranscribeClient transcribeClient;
    @Mock private S3Client s3Client;
    @Mock private CallTranscriptService callTranscriptService;
    @Mock private CallTelemetryService callTelemetryService;
    @Mock private CallRecordingRepository recordingRepository;
    @Mock private CallAttendeeRepository callAttendeeRepository;
    @Mock private KvsArchivedMediaExportService kvsArchivedMediaExportService;
    @Mock private KvsAudioTranscodeService kvsAudioTranscodeService;

    private PostCallTranscriptionService service;

    @BeforeEach
    void setUp() {
        service = new PostCallTranscriptionService();
        ReflectionTestUtils.setField(service, "transcribeClient", transcribeClient);
        ReflectionTestUtils.setField(service, "s3Client", s3Client);
        ReflectionTestUtils.setField(service, "callTranscriptService", callTranscriptService);
        ReflectionTestUtils.setField(service, "callTelemetryService", callTelemetryService);
        ReflectionTestUtils.setField(service, "recordingRepository", recordingRepository);
        ReflectionTestUtils.setField(service, "callAttendeeRepository", callAttendeeRepository);
        ReflectionTestUtils.setField(service, "kvsArchivedMediaExportService", kvsArchivedMediaExportService);
        ReflectionTestUtils.setField(service, "kvsAudioTranscodeService", kvsAudioTranscodeService);
    }

    @Test
    @DisplayName("F7: transcribes persisted KVS stream as WAV before MP4 fallback")
    void transcribeAndCleanup_kvsStreamMapping_usesWavTranscribe() throws Exception {
        final CallRecording recording = recording();
        final CallAttendee attendee = attendee();
        final Path raw = Files.createTempFile("kvs-test", ".mkv");
        final Path wav = Files.createTempFile("kvs-test", ".wav");
        when(callAttendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(attendee));
        when(kvsArchivedMediaExportService.exportAttendeeRange(
                        any(String.class), any(java.time.Instant.class), any(java.time.Instant.class)))
                .thenReturn(raw);
        when(kvsAudioTranscodeService.toWav(raw)).thenReturn(wav);
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().build());
        when(transcribeClient.startTranscriptionJob(any(StartTranscriptionJobRequest.class)))
                .thenReturn(StartTranscriptionJobResponse.builder().build());
        when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                .thenReturn(completedJob());
        when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(transcriptStream());
        when(callTranscriptService.recordSegments(
                        any(String.class),
                        any(Long.class),
                        org.mockito.ArgumentMatchers.<List<TranscriptSegmentInput>>any()))
                .thenReturn(1);
        when(recordingRepository.findById(1L)).thenReturn(Optional.of(recording));

        service.transcribeAndCleanup(CALL_ID, recording, PLAYABLE_KEY);

        final ArgumentCaptor<StartTranscriptionJobRequest> captor =
                ArgumentCaptor.forClass(StartTranscriptionJobRequest.class);
        verify(transcribeClient).startTranscriptionJob(captor.capture());
        assertThat(captor.getValue().mediaFormat()).isEqualTo(MediaFormat.WAV);
        assertThat(captor.getValue().settings().showSpeakerLabels()).isFalse();
        verify(callTranscriptService)
                .recordSegments(
                        any(String.class),
                        any(Long.class),
                        org.mockito.ArgumentMatchers.<List<TranscriptSegmentInput>>any());
        verify(kvsArchivedMediaExportService)
                .exportAttendeeRange(any(String.class), any(java.time.Instant.class), any(java.time.Instant.class));

        Files.deleteIfExists(raw);
        Files.deleteIfExists(wav);
    }

    @Test
    @DisplayName("falls back to MP4 diarization when no KVS stream mapping exists")
    void transcribeAndCleanup_noKvsMapping_usesMp4Fallback() throws Exception {
        final CallRecording recording = recording();
        when(callAttendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of());
        when(transcribeClient.startTranscriptionJob(any(StartTranscriptionJobRequest.class)))
                .thenReturn(StartTranscriptionJobResponse.builder().build());
        when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                .thenReturn(completedJob());
        when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(transcriptStream());
        when(recordingRepository.findById(1L)).thenReturn(Optional.of(recording));

        service.transcribeAndCleanup(CALL_ID, recording, PLAYABLE_KEY);

        final ArgumentCaptor<StartTranscriptionJobRequest> captor =
                ArgumentCaptor.forClass(StartTranscriptionJobRequest.class);
        verify(transcribeClient).startTranscriptionJob(captor.capture());
        assertThat(captor.getValue().mediaFormat()).isEqualTo(MediaFormat.MP4);
        assertThat(captor.getValue().settings().showSpeakerLabels()).isTrue();
        verify(kvsArchivedMediaExportService, never())
                .exportAttendeeRange(any(String.class), any(java.time.Instant.class), any(java.time.Instant.class));
    }

    @Test
    @DisplayName("F7: continues after one empty attendee transcript and stores the next attendee")
    void transcribeAndCleanup_oneEmptyKvsTranscript_continuesToNextAttendee() throws Exception {
        final CallRecording recording = recording();
        final CallAttendee emptyAttendee = attendee();
        emptyAttendee.setId(10L);
        emptyAttendee.setChimeAttendeeId("att-empty");
        emptyAttendee.setUserId(1L);
        emptyAttendee.setRole("PATIENT");
        final CallAttendee speakingAttendee = attendee();
        speakingAttendee.setId(11L);
        speakingAttendee.setChimeAttendeeId("att-speaking");
        speakingAttendee.setUserId(2L);
        speakingAttendee.setRole("CAREGIVER");
        final Path raw1 = Files.createTempFile("kvs-empty", ".mkv");
        final Path raw2 = Files.createTempFile("kvs-speaking", ".mkv");
        final Path wav1 = Files.createTempFile("kvs-empty", ".wav");
        final Path wav2 = Files.createTempFile("kvs-speaking", ".wav");

        when(callAttendeeRepository.findByCallId(CALL_ID)).thenReturn(List.of(emptyAttendee, speakingAttendee));
        when(kvsArchivedMediaExportService.exportAttendeeRange(
                        any(String.class), any(java.time.Instant.class), any(java.time.Instant.class)))
                .thenReturn(raw1, raw2);
        when(kvsAudioTranscodeService.toWav(raw1)).thenReturn(wav1);
        when(kvsAudioTranscodeService.toWav(raw2)).thenReturn(wav2);
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().build());
        when(transcribeClient.startTranscriptionJob(any(StartTranscriptionJobRequest.class)))
                .thenReturn(StartTranscriptionJobResponse.builder().build());
        when(transcribeClient.getTranscriptionJob(any(GetTranscriptionJobRequest.class)))
                .thenReturn(completedJob());
        doReturn(emptyTranscriptStream())
                .doReturn(transcriptStream())
                .when(s3Client)
                .getObject(any(GetObjectRequest.class));
        when(callTranscriptService.recordSegments(
                        any(String.class),
                        any(Long.class),
                        org.mockito.ArgumentMatchers.<List<TranscriptSegmentInput>>any()))
                .thenReturn(1);
        when(recordingRepository.findById(1L)).thenReturn(Optional.of(recording));

        service.transcribeAndCleanup(CALL_ID, recording, PLAYABLE_KEY);

        final ArgumentCaptor<StartTranscriptionJobRequest> captor =
                ArgumentCaptor.forClass(StartTranscriptionJobRequest.class);
        verify(transcribeClient, times(2)).startTranscriptionJob(captor.capture());
        assertThat(captor.getAllValues()).allMatch(request -> request.mediaFormat() == MediaFormat.WAV);
        verify(callTranscriptService, times(1))
                .recordSegments(
                        any(String.class),
                        any(Long.class),
                        org.mockito.ArgumentMatchers.<List<TranscriptSegmentInput>>any());

        Files.deleteIfExists(raw1);
        Files.deleteIfExists(raw2);
        Files.deleteIfExists(wav1);
        Files.deleteIfExists(wav2);
    }

    private static CallRecording recording() {
        final CallRecording recording = new CallRecording();
        recording.setId(1L);
        recording.setCallId(CALL_ID);
        recording.setS3Bucket(BUCKET);
        recording.setS3Prefix(PREFIX);
        recording.setStartedAt(LocalDateTime.of(2026, 7, 3, 17, 0));
        recording.setEndedAt(LocalDateTime.of(2026, 7, 3, 17, 2));
        return recording;
    }

    private static CallAttendee attendee() {
        final CallAttendee attendee = new CallAttendee();
        attendee.setId(10L);
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId("att-caregiver");
        attendee.setKvsStreamArn(STREAM_ARN);
        attendee.setUserId(2L);
        attendee.setRole("CAREGIVER");
        attendee.setJoinedAt(LocalDateTime.of(2026, 7, 3, 17, 0));
        return attendee;
    }

    private static GetTranscriptionJobResponse completedJob() {
        return GetTranscriptionJobResponse.builder()
                .transcriptionJob(
                        TranscriptionJob.builder()
                                .transcriptionJobStatus(TranscriptionJobStatus.COMPLETED)
                                .build())
                .build();
    }

    private static ResponseInputStream<GetObjectResponse> transcriptStream() {
        final String json =
                """
                {"results":{"items":[
                  {"type":"pronunciation","start_time":"0.10","end_time":"0.40","alternatives":[{"content":"hello"}]},
                  {"type":"punctuation","alternatives":[{"content":"."}]}
                ]}}
                """;
        return new ResponseInputStream<>(
                GetObjectResponse.builder().build(),
                AbortableInputStream.create(new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))));
    }

    private static ResponseInputStream<GetObjectResponse> emptyTranscriptStream() {
        final String json =
                """
                {"results":{"transcripts":[{"transcript":""}],"items":[],"audio_segments":[]}}
                """;
        return new ResponseInputStream<>(
                GetObjectResponse.builder().build(),
                AbortableInputStream.create(new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))));
    }
}
