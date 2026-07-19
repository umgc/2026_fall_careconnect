package com.careconnect.service;

import com.careconnect.model.CallRecording;
import com.careconnect.repository.CallRecordingRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaCapturePipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaConcatenationPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaConcatenationPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaCapturePipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaCapturePipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaCapturePipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaConcatenationPipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineStatus;
import software.amazon.awssdk.services.iam.IamClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CommonPrefix;
import software.amazon.awssdk.services.s3.model.CORSRule;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.PutBucketCorsRequest;
import software.amazon.awssdk.services.s3.model.PutBucketPolicyRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityResponse;

import java.net.URI;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Unit tests for CallRecordingService.
 *
 * Uses pure Mockito (no Spring context). @Value fields are injected
 * via ReflectionTestUtils in @BeforeEach.
 *
 * AWS SDK v2 methods have both (Request) and (Consumer<Builder>) overloads;
 * typed matchers such as any(SomeRequest.class) are used throughout to avoid
 * ambiguity.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("CallRecordingService Tests")
class CallRecordingServiceTest {

    // ── Mocked dependencies ───────────────────────────────────────────────────

    @Mock private ChimeSdkMediaPipelinesClient pipelinesClient;
    @Mock private StsClient stsClient;
    @Mock private S3Presigner s3Presigner;
    @Mock private S3Client s3Client;
    @Mock private IamClient iamClient;
    @Mock private ChimeService chimeService;
    @Mock private CallRecordingRepository recordingRepository;
    @Mock private PostCallTranscriptionService postCallTranscriptionService;

    @InjectMocks
    private CallRecordingService service;

    // ── Constants used across tests ───────────────────────────────────────────

    private static final String CALL_ID          = "call-abc-123";
    private static final String MEETING_ID        = "meeting-uuid-001";
    private static final String PIPELINE_ID       = "pipeline-uuid-001";
    private static final String BUCKET            = "careconnect-recordings-123456789012-us-east-1";
    private static final String S3_PREFIX         = "recordings/" + CALL_ID + "/20260312-100000/";
    private static final String ACCOUNT_ID        = "123456789012";
    private static final long   USER_ID           = 42L;

    @BeforeEach
    void setUp() {
        // Inject @Value fields that Mockito cannot set automatically
        ReflectionTestUtils.setField(service, "recordingEnabled",      true);
        ReflectionTestUtils.setField(service, "presignedUrlTtlMinutes", 15);
        ReflectionTestUtils.setField(service, "rawCleanupEnabled",      true);
        ReflectionTestUtils.setField(service, "corsAllowedOrigins",     "http://localhost:*");
        ReflectionTestUtils.setField(service, "recordingCorsAllowWildcard", true);

        // Pre-wire STS so account-ID resolution succeeds in any test that
        // exercises the happy path. The service calls the no-arg overload.
        GetCallerIdentityResponse identity =
                GetCallerIdentityResponse.builder().account(ACCOUNT_ID).build();
        when(stsClient.getCallerIdentity()).thenReturn(identity);

        lenient()
                .when(s3Client.putBucketPolicy(any(PutBucketPolicyRequest.class)))
                .thenReturn(
                        software.amazon.awssdk.services.s3.model.PutBucketPolicyResponse.builder()
                                .build());
        lenient()
                .when(s3Client.putBucketCors(any(PutBucketCorsRequest.class)))
                .thenReturn(
                        software.amazon.awssdk.services.s3.model.PutBucketCorsResponse.builder()
                                .build());
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  startRecording
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("startRecording")
    class StartRecordingTests {

        @Test
        @DisplayName("returns DISABLED when recordingEnabled=false")
        void startRecording_whenDisabled_returnsDisabledStatus() {
            ReflectionTestUtils.setField(service, "recordingEnabled", false);

            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);

            assertThat(result).containsEntry("status", "DISABLED");
            verifyNoInteractions(chimeService, pipelinesClient, recordingRepository);
        }

        @Test
        @DisplayName("returns ERROR when no active Chime meeting found for callId")
        void startRecording_noMeeting_returnsError() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(null);

            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);

            assertThat(result).containsEntry("status", "ERROR");
            assertThat(result.get("message").toString()).contains(CALL_ID);
        }

        @Test
        @DisplayName("returns ALREADY_RECORDING when pipeline already active for callId")
        void startRecording_alreadyRecording_returnsAlreadyRecordingStatus() {
            // Seed the activePipelineIds map via a successful start first
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);

            // Fake STS identity so resolveOrCreateRecordingBucket returns a bucket name
            // Build a minimal CreateMediaCapturePipelineResponse
            MediaCapturePipeline pipeline = MediaCapturePipeline.builder()
                    .mediaPipelineId(PIPELINE_ID)
                    .build();
            CreateMediaCapturePipelineResponse createResp =
                    CreateMediaCapturePipelineResponse.builder()
                            .mediaCapturePipeline(pipeline)
                            .build();

            when(pipelinesClient.createMediaCapturePipeline(
                    any(CreateMediaCapturePipelineRequest.class)))
                    .thenReturn(createResp);

            // Trigger bucket creation to succeed (S3 putBucketPolicy returns a response)
            when(s3Client.putBucketPolicy(any(
                    software.amazon.awssdk.services.s3.model.PutBucketPolicyRequest.class)))
                    .thenReturn(software.amazon.awssdk.services.s3.model.PutBucketPolicyResponse.builder().build());

            service.startRecording(CALL_ID, null); // first call registers pipeline (null userId avoids RECORDING_CLAIMED)

            CallRecording active = buildRecording("STARTED");
            active.setInitiatedByUserId(null);
            active.setLifecycleStatus(
                    com.careconnect.model.RecordingLifecycleStatus.ACTIVE);
            when(recordingRepository.findActiveByCallId(CALL_ID))
                    .thenReturn(Optional.of(active));

            // Second call observes the durable active owner.
            Map<String, Object> result = service.startRecording(CALL_ID, null);

            assertThat(result).containsEntry("status", "ALREADY_RECORDING");
            assertThat(result).containsKey("pipelineId");
        }

        @Test
        @DisplayName("returns UNAVAILABLE when AWS pipeline client is null")
        void startRecording_awsUnavailable_returnsUnavailable() {
            // Make pipelinesClient null so isAwsAvailable() returns false
            ReflectionTestUtils.setField(service, "pipelinesClient", null);

            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);

            // STS still available, but pipelinesClient is null → resolveOrCreateRecordingBucket
            // returns a bucket name (no S3 call needed), but isAwsAvailable() is false.
            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);

            assertThat(result.get("status").toString()).isIn("UNAVAILABLE", "ERROR");
        }

        @Test
        @DisplayName("happy path — creates pipeline and returns STARTED status")
        void startRecording_whenEnabled_callsPipelineAndReturnsStarted() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);

            MediaCapturePipeline pipeline = MediaCapturePipeline.builder()
                    .mediaPipelineId(PIPELINE_ID)
                    .build();
            CreateMediaCapturePipelineResponse createResp =
                    CreateMediaCapturePipelineResponse.builder()
                            .mediaCapturePipeline(pipeline)
                            .build();
            when(pipelinesClient.createMediaCapturePipeline(
                    any(CreateMediaCapturePipelineRequest.class)))
                    .thenReturn(createResp);

            // Suppress bucket-policy call (returns response object, not void)
            when(s3Client.putBucketPolicy(any(
                    software.amazon.awssdk.services.s3.model.PutBucketPolicyRequest.class)))
                    .thenReturn(software.amazon.awssdk.services.s3.model.PutBucketPolicyResponse.builder().build());

            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);

            assertThat(result).containsEntry("status", "STARTED");
            assertThat(result).containsEntry("pipelineId", PIPELINE_ID);
            assertThat(result).containsKey("s3Bucket");
            assertThat(result).containsKey("s3Prefix");

            verify(recordingRepository).saveAndFlush(any(CallRecording.class));
            verify(pipelinesClient).createMediaCapturePipeline(
                    any(CreateMediaCapturePipelineRequest.class));
        }

        @Test
        @DisplayName("returns ERROR and saves FAILED recording when pipeline creation throws")
        void startRecording_pipelineCreationThrows_returnsError() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(pipelinesClient.createMediaCapturePipeline(
                    any(CreateMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("Chime quota exceeded"));
            when(s3Client.putBucketPolicy(any(
                    software.amazon.awssdk.services.s3.model.PutBucketPolicyRequest.class)))
                    .thenReturn(software.amazon.awssdk.services.s3.model.PutBucketPolicyResponse.builder().build());

            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);

            assertThat(result).containsEntry("status", "ERROR");
            assertThat(result.get("message").toString()).contains("Chime quota exceeded");
            verify(recordingRepository).save(argThat(rec ->
                    "FAILED".equals(rec.getStatus()) && CALL_ID.equals(rec.getCallId())));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  stopRecording
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("stopRecording")
    class StopRecordingTests {

        @Test
        @DisplayName("returns NOT_RECORDING when no pipeline active and DB is empty")
        void stopRecording_whenNoActiveRecording_returnsNotRecording() {
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "NOT_RECORDING");
            verifyNoInteractions(pipelinesClient);
        }

        @Test
        @DisplayName("returns NOT_RECORDING when DB has a non-STARTED record only")
        void stopRecording_dbHasStoppedRecord_returnsNotRecording() {
            CallRecording rec = buildRecording("STOPPED");
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "NOT_RECORDING");
        }

        @Test
        @DisplayName("deletes pipeline and returns STOPPED when active pipeline found in DB")
        void stopRecording_whenActive_deletesPipelineAndReturnsStopped() {
            CallRecording rec = buildRecording("STARTED");
            rec.setPipelineId(PIPELINE_ID);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);

            // DB lookup (used when activePipelineIds map is empty after restart)
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            // Capture-pipeline ARN lookup
            MediaCapturePipeline capturePipeline = MediaCapturePipeline.builder()
                    .mediaPipelineId(PIPELINE_ID)
                    .mediaPipelineArn("arn:aws:chime::" + ACCOUNT_ID + ":mediaPipeline/" + PIPELINE_ID)
                    .build();
            GetMediaCapturePipelineResponse getCapResp = GetMediaCapturePipelineResponse.builder()
                    .mediaCapturePipeline(capturePipeline)
                    .build();
            when(pipelinesClient.getMediaCapturePipeline(
                    any(GetMediaCapturePipelineRequest.class)))
                    .thenReturn(getCapResp);

            // Concatenation pipeline creation
            MediaConcatenationPipeline concatPipeline = MediaConcatenationPipeline.builder()
                    .mediaPipelineId("concat-pipeline-001")
                    .build();
            CreateMediaConcatenationPipelineResponse concatResp =
                    CreateMediaConcatenationPipelineResponse.builder()
                            .mediaConcatenationPipeline(concatPipeline)
                            .build();
            when(pipelinesClient.createMediaConcatenationPipeline(
                    any(CreateMediaConcatenationPipelineRequest.class)))
                    .thenReturn(concatResp);

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "STOPPED");
            assertThat(rec.getStatus()).isEqualTo("STOPPED");
            verify(pipelinesClient).deleteMediaCapturePipeline(
                    any(DeleteMediaCapturePipelineRequest.class));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  getRecordingStatus
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getRecordingStatus")
    class GetRecordingStatusTests {

        @Test
        @DisplayName("returns NO_RECORDING when repository has no entry for callId")
        void getRecordingStatus_noRecording_returnsNoRecording() {
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            Map<String, Object> result = service.getRecordingStatus(CALL_ID);

            assertThat(result).containsEntry("status", "NO_RECORDING");
            assertThat(result).containsEntry("callId", CALL_ID);
        }

        @Test
        @DisplayName("returns recording metadata map when recording exists")
        void getRecordingStatus_withRecording_returnsStatus() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setPipelineId(PIPELINE_ID);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("NOT_REQUESTED");
            rec.setLifecycleStatus(
                    com.careconnect.model.RecordingLifecycleStatus.ACTIVE);
            rec.setLifecycleStatus(
                    com.careconnect.model.RecordingLifecycleStatus.ACTIVE);

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            // s3Client.listObjectsV2 is called from resolvePlayableVideoKeyWithoutRefresh
            // via refreshConcatenationStatus → return empty to avoid NPE
            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            Map<String, Object> result = service.getRecordingStatus(CALL_ID);

            assertThat(result).containsEntry("callId", CALL_ID);
            assertThat(result).containsEntry("status", "STOPPED");
            assertThat(result).containsKey("pipelineId");
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  generatePlaybackUrl
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("generatePlaybackUrl")
    class GeneratePlaybackUrlTests {

        @Test
        @DisplayName("returns NO_RECORDING when repository has no entry for callId")
        void generatePlaybackUrl_noRecording_returnsNoRecording() {
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("status", "NO_RECORDING");
        }

        @Test
        @DisplayName("returns UNAVAILABLE when S3Presigner is null")
        void generatePlaybackUrl_presignerNull_returnsUnavailable() {
            ReflectionTestUtils.setField(service, "s3Presigner", null);

            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("NOT_REQUESTED");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("status", "UNAVAILABLE");
        }

        @Test
        @DisplayName("returns PROCESSING status when concatenated video not yet available in S3")
        void generatePlaybackUrl_videoNotYetReady_returnsProcessing() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId("concat-pipe-001");
            rec.setConcatenationStatus("PROCESSING");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            // S3 returns empty — no .mp4 found yet
            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("status", "PROCESSING");
            assertThat(result).containsEntry("playbackReady", false);
        }

        @Test
        @DisplayName("system transcription capture never returns a playback URL")
        void generatePlaybackUrl_systemCapture_suppressesPlayback() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setInitiatedByUserId(null);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("READY");
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result)
                    .containsEntry("status", "TRANSCRIPTION_ONLY")
                    .containsEntry("playbackReady", false)
                    .doesNotContainKey("playbackUrl");
            verify(s3Presigner, never()).presignGetObject(any(GetObjectPresignRequest.class));
        }

        @Test
        @DisplayName("SENT-CLIP-002 returns presigned URL with recordingStartedAt when video is available")
        void generatePlaybackUrl_withRecording_returnsUrl() throws Exception {
            String stitchedKey = S3_PREFIX + "concatenated/composited-video/concat-pipe-001.mp4";

            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId("concat-pipe-001");
            rec.setConcatenationStatus("READY");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            // Return the stitched .mp4 when the exact key prefix is queried
            software.amazon.awssdk.services.s3.model.S3Object s3Obj =
                    software.amazon.awssdk.services.s3.model.S3Object.builder()
                            .key(stitchedKey)
                            .build();
            ListObjectsV2Response hitListing = ListObjectsV2Response.builder()
                    .contents(List.of(s3Obj))
                    .isTruncated(false)
                    .build();
            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();

            // The service calls listObjectsV2 multiple times; return hit for the
            // exact-key probe and empty for everything else.
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenAnswer(inv -> {
                        ListObjectsV2Request req = inv.getArgument(0);
                        if (req.prefix() != null && req.prefix().equals(stitchedKey)) {
                            return hitListing;
                        }
                        if (req.prefix() != null && req.prefix().contains("composited-video")) {
                            return hitListing;
                        }
                        return emptyListing;
                    });

            // Mock presigner
            PresignedGetObjectRequest presigned = mock(PresignedGetObjectRequest.class);
            when(presigned.url()).thenReturn(new URI("https://s3.example.com/presigned-url").toURL());
            when(s3Presigner.presignGetObject(any(GetObjectPresignRequest.class)))
                    .thenReturn(presigned);

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsKey("playbackUrl");
            assertThat(result.get("playbackUrl").toString()).contains("presigned-url");
            assertThat(result).containsEntry("playbackReady", true);
            assertThat(result).containsKey("recordingStartedAt");
            assertThat(result.get("recordingStartedAt").toString()).endsWith("Z");
            assertThat(result.get("recordingStartedAt"))
                    .isEqualTo(
                            rec.getStartedAt()
                                    .atZone(java.time.ZoneOffset.UTC)
                                    .toInstant()
                                    .toString());
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  purgeRecordingsForCall
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("purgeRecordingsForCall")
    class PurgeRecordingsForCallTests {

        @Test
        @DisplayName("returns zero counts when callId is null or blank")
        void purgeRecordingsForCall_nullCallId_returnsZeroCounts() {
            Map<String, Object> result = service.purgeRecordingsForCall(null);

            assertThat(result).containsEntry("deletedDbRows", 0L);
            assertThat(result).containsEntry("deletedS3Objects", 0L);
            verifyNoInteractions(recordingRepository);
        }

        @Test
        @DisplayName("deletes DB rows and returns correct counts")
        void purgeRecordingsForCall_deletesRecordings() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);

            when(recordingRepository.findByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(List.of(rec));

            // S3 list returns empty so deleteObjectsUnderPrefix does nothing
            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            Map<String, Object> result = service.purgeRecordingsForCall(CALL_ID);

            assertThat(result).containsEntry("callId", CALL_ID);
            assertThat(result).containsEntry("deletedDbRows", 1L);
            verify(recordingRepository).deleteByCallId(CALL_ID);
        }

        @Test
        @DisplayName("returns zero DB rows when no recordings exist for callId")
        void purgeRecordingsForCall_noRecordings_returnsZero() {
            when(recordingRepository.findByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Collections.emptyList());

            Map<String, Object> result = service.purgeRecordingsForCall(CALL_ID);

            assertThat(result).containsEntry("deletedDbRows", 0L);
            verify(recordingRepository, never()).deleteByCallId(any());
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  purgeAllRecordings
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("purgeAllRecordings")
    class PurgeAllRecordingsTests {

        @Test
        @DisplayName("deletes all DB rows and returns summary map")
        void purgeAllRecordings_deletesAll() {
            when(recordingRepository.count()).thenReturn(3L);

            // S3 listing returns empty — S3 delete path is a no-op in this test
            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            Map<String, Object> result = service.purgeAllRecordings();

            assertThat(result).containsEntry("deletedDbRows", 3L);
            verify(recordingRepository).deleteAll();
        }

        @Test
        @DisplayName("S3 objects are deleted when bucket is resolved")
        void purgeAllRecordings_whenBucketResolved_deletesS3Objects() {
            when(recordingRepository.count()).thenReturn(1L);

            // Pre-populate the cached bucket so resolveOrCreateRecordingBucket is skipped
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", BUCKET);

            software.amazon.awssdk.services.s3.model.S3Object obj =
                    software.amazon.awssdk.services.s3.model.S3Object.builder()
                            .key("recordings/call-abc/20260312-100000/audio/chunk.mp4")
                            .build();
            ListObjectsV2Response page = ListObjectsV2Response.builder()
                    .contents(List.of(obj))
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(page);

            Map<String, Object> result = service.purgeAllRecordings();

            assertThat(result).containsEntry("deletedDbRows", 1L);
            assertThat((long) (Long) result.get("deletedS3Objects")).isGreaterThanOrEqualTo(1L);
            verify(s3Client, atLeastOnce())
                    .deleteObjects(any(software.amazon.awssdk.services.s3.model.DeleteObjectsRequest.class));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  cleanupRawArtifactsForCall
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("cleanupRawArtifactsForCall")
    class CleanupRawArtifactsTests {

        @Test
        @DisplayName("returns NO_RECORDING when no entry in DB")
        void cleanupRawArtifactsForCall_noRecording_returnsNoRecording() {
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            Map<String, Object> result = service.cleanupRawArtifactsForCall(CALL_ID);

            assertThat(result).containsEntry("status", "NO_RECORDING");
        }

        @Test
        @DisplayName("returns PLAYBACK_NOT_READY when stitched video not yet in S3")
        void cleanupRawArtifactsForCall_videoNotReady_returnsPlaybackNotReady() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("PROCESSING");
            rec.setConcatenationPipelineId("concat-pipe-001");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            Map<String, Object> result = service.cleanupRawArtifactsForCall(CALL_ID);

            assertThat(result).containsEntry("status", "PLAYBACK_NOT_READY");
            assertThat(result).containsEntry("deletedObjects", 0L);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  getRecordingsByUser
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getRecordingsByUser")
    class GetRecordingsByUserTests {

        @Test
        @DisplayName("returns mapped recordings for the given userId")
        void getRecordingsByUser_returnsUserRecordings() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("NOT_REQUESTED");

            when(recordingRepository.findByInitiatedByUserIdOrderByStartedAtDesc(USER_ID))
                    .thenReturn(List.of(rec));

            // resolvePlayableVideoKeyWithoutRefresh needs s3Client response
            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            List<Map<String, Object>> results = service.getRecordingsByUser(USER_ID);

            assertThat(results).hasSize(1);
            assertThat(results.get(0)).containsEntry("callId", CALL_ID);
        }

        @Test
        @DisplayName("returns empty list when no recordings exist for userId")
        void getRecordingsByUser_noRecordings_returnsEmptyList() {
            when(recordingRepository.findByInitiatedByUserIdOrderByStartedAtDesc(USER_ID))
                    .thenReturn(Collections.emptyList());

            List<Map<String, Object>> results = service.getRecordingsByUser(USER_ID);

            assertThat(results).isEmpty();
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  getAllRecordings
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getAllRecordings")
    class GetAllRecordingsTests {

        @Test
        @DisplayName("returns all recordings from the repository")
        void getAllRecordings_returnsAllRecordings() {
            CallRecording rec1 = buildRecording("STARTED");
            rec1.setS3Bucket(BUCKET);
            rec1.setS3Prefix(S3_PREFIX);
            rec1.setConcatenationStatus("NOT_REQUESTED");

            CallRecording rec2 = buildRecording("STOPPED");
            rec2.setCallId("call-xyz-999");
            rec2.setS3Bucket(BUCKET);
            rec2.setS3Prefix("recordings/call-xyz-999/20260312-110000/");
            rec2.setConcatenationStatus("NOT_REQUESTED");

            when(recordingRepository.findAll()).thenReturn(List.of(rec1, rec2));

            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            List<Map<String, Object>> results = service.getAllRecordings();

            assertThat(results).hasSize(2);
        }

        @Test
        @DisplayName("returns empty list when repository is empty")
        void getAllRecordings_emptyRepository_returnsEmptyList() {
            when(recordingRepository.findAll()).thenReturn(Collections.emptyList());

            List<Map<String, Object>> results = service.getAllRecordings();

            assertThat(results).isEmpty();
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  getRecordingsForCall
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getRecordingsForCall")
    class GetRecordingsForCallTests {

        @Test
        @DisplayName("returns all recordings for the specified callId")
        void getRecordingsForCall_returnsRecordingsForCall() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("NOT_REQUESTED");

            when(recordingRepository.findByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(List.of(rec));

            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            List<Map<String, Object>> results = service.getRecordingsForCall(CALL_ID);

            assertThat(results).hasSize(1);
            assertThat(results.get(0)).containsEntry("callId", CALL_ID);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  recordingEnabled=false edge cases
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("additional edge paths")
    class AdditionalEdgePathTests {

        @Test
        @DisplayName("stopRecording remains retryable when AWS is unavailable after DB recovery")
        void stopRecording_awsUnavailableAfterDbRecovery_remainsRetryable() {
            CallRecording rec = buildRecording("STARTED");
            rec.setPipelineId(PIPELINE_ID);

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            ReflectionTestUtils.setField(service, "pipelinesClient", null);

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "RETRYABLE_FAILURE");
            assertThat(result).containsEntry("recordingStatus", "STOP_RETRYABLE");
            assertThat(result).containsEntry("pipelineId", PIPELINE_ID);
            assertThat(rec.getStatus()).isEqualTo("STOP_RETRYABLE");
        }

        @Test
        @DisplayName("stopRecording keeps deletion failures retryable")
        void stopRecording_deleteFailure_remainsRetryable() {
            CallRecording rec = buildRecording("STARTED");
            rec.setPipelineId(PIPELINE_ID);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaCapturePipeline(any(GetMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("capture lookup failed"));
            doThrow(new RuntimeException("delete failed"))
                    .when(pipelinesClient)
                    .deleteMediaCapturePipeline(any(DeleteMediaCapturePipelineRequest.class));

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "RETRYABLE_FAILURE");
            assertThat(result).containsEntry("recordingStatus", "STOP_RETRYABLE");
            assertThat(result.get("message").toString()).contains("delete failed");
            assertThat(rec.getStatus()).isEqualTo("STOP_RETRYABLE");
        }

        @Test
        @DisplayName("getRecordingStatus includes liveStatus when an active pipeline is tracked")
        void getRecordingStatus_activePipeline_includesLiveStatus() {
            CallRecording rec = buildRecording("STARTED");
            rec.setPipelineId(PIPELINE_ID);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("NOT_REQUESTED");
            rec.setLifecycleStatus(
                    com.careconnect.model.RecordingLifecycleStatus.ACTIVE);

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(ListObjectsV2Response.builder().contents(Collections.emptyList()).isTruncated(false).build());
            when(pipelinesClient.getMediaCapturePipeline(any(GetMediaCapturePipelineRequest.class)))
                    .thenReturn(GetMediaCapturePipelineResponse.builder()
                            .mediaCapturePipeline(MediaCapturePipeline.builder()
                                    .mediaPipelineId(PIPELINE_ID)
                                    .status("Initializing")
                                    .build())
                            .build());

            Map<String, Object> result = service.getRecordingStatus(CALL_ID);

            assertThat(result).containsEntry("liveStatus", "Initializing");
        }

        @Test
        @DisplayName("generatePlaybackUrl returns ERROR when recording has no stored S3 location")
        void generatePlaybackUrl_missingS3Location_returnsError() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(null);
            rec.setS3Prefix(null);

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("status", "ERROR");
            assertThat(result.get("message").toString()).contains("no S3 location");
        }

        @Test
        @DisplayName("generatePlaybackUrl returns ERROR when presigning throws")
        void generatePlaybackUrl_presignThrows_returnsError() {
            String stitchedKey = S3_PREFIX + "concatenated/video/concat-pipe-001.mp4";
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId("concat-pipe-001");
            rec.setConcatenationStatus("READY");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenAnswer(inv -> {
                        ListObjectsV2Request req = inv.getArgument(0);
                        if (req.prefix() != null && req.prefix().contains("concatenated")) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder()
                                            .key(stitchedKey)
                                            .build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        return ListObjectsV2Response.builder()
                                .contents(Collections.emptyList())
                                .isTruncated(false)
                                .build();
                    });
            when(s3Presigner.presignGetObject(any(GetObjectPresignRequest.class)))
                    .thenThrow(new RuntimeException("presign failed"));

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("status", "ERROR");
            assertThat(result.get("message").toString()).contains("presign failed");
        }

        @Test
        @DisplayName("generatePlaybackUrl falls back to legacy video chunks when concatenation was never requested")
        void generatePlaybackUrl_legacyChunkPath_returnsUrl() throws Exception {
            String legacyKey = S3_PREFIX + "video/chunk-001.mp4";
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId(null);
            rec.setConcatenationStatus("NOT_REQUESTED");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenAnswer(inv -> {
                        ListObjectsV2Request req = inv.getArgument(0);
                        if (req.prefix() != null && req.prefix().endsWith("video/")) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key(legacyKey).build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        return ListObjectsV2Response.builder().contents(Collections.emptyList()).isTruncated(false).build();
                    });
            PresignedGetObjectRequest presigned = mock(PresignedGetObjectRequest.class);
            when(presigned.url()).thenReturn(new URI("https://s3.example.com/legacy").toURL());
            when(s3Presigner.presignGetObject(any(GetObjectPresignRequest.class))).thenReturn(presigned);

            Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("playbackReady", true);
            assertThat(result).containsEntry("s3Key", legacyKey);
        }

        @Test
        @DisplayName("getRecordingStatus marks concatenation failed when pipeline status is failed")
        void getRecordingStatus_failedConcatenation_updatesErrorMessage() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId("concat-pipe-001");
            rec.setConcatenationStatus("PROCESSING");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(ListObjectsV2Response.builder().contents(Collections.emptyList()).isTruncated(false).build());
            when(pipelinesClient.getMediaPipeline(any(software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineRequest.class)))
                    .thenReturn(GetMediaPipelineResponse.builder()
                            .mediaPipeline(MediaPipeline.builder()
                                    .mediaConcatenationPipeline(MediaConcatenationPipeline.builder()
                                            .status(MediaPipelineStatus.FAILED)
                                            .build())
                                    .build())
                            .build());

            Map<String, Object> result = service.getRecordingStatus(CALL_ID);

            assertThat(result).containsEntry("concatenationStatus", "FAILED");
            assertThat(result.get("errorMessage").toString()).contains("no stitched video was found");
        }

        @Test
        @DisplayName("cleanupRawArtifactsForCall deletes managed raw prefixes and stray pipeline markers once playback is ready")
        void cleanupRawArtifactsForCall_readyPlayback_cleansArtifacts() {
            String playableKey = S3_PREFIX + "concatenated/composited-video/final.mp4";
            String foreignPrefix = "12345678-1234-1234-1234-1234567890ab/";
            CallRecording rec = buildRecording("STOPPED");
            rec.setPipelineId("12345678-1234-1234-1234-1234567890ab");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId("final");
            rec.setConcatenationStatus("READY");

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenAnswer(inv -> {
                        ListObjectsV2Request req = inv.getArgument(0);
                        String prefix = req.prefix();
                        if (playableKey.equals(prefix)) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key(playableKey).build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        if (prefix != null && prefix.contains("composited-video")) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key(playableKey).build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        if (prefix == null && "/".equals(req.delimiter())) {
                            return ListObjectsV2Response.builder()
                                    .commonPrefixes(List.of(CommonPrefix.builder().prefix(foreignPrefix).build()))
                                    .contents(Collections.emptyList())
                                    .isTruncated(false)
                                    .build();
                        }
                        if ((foreignPrefix + "video/").equals(prefix)) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key(foreignPrefix + "video/final.mp4").build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        if (prefix != null && (prefix.endsWith("audio/") || prefix.endsWith("video/") || prefix.endsWith("content/")
                                || prefix.endsWith("data-channel/") || prefix.endsWith("meeting-events/") || prefix.endsWith("transcription-messages/"))) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key(prefix + "obj").build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        if (foreignPrefix.equals(prefix) || foreignPrefix.substring(0, foreignPrefix.length() - 1).equals(prefix)) {
                            return ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key(prefix).build()))
                                    .isTruncated(false)
                                    .build();
                        }
                        return ListObjectsV2Response.builder().contents(Collections.emptyList()).isTruncated(false).build();
                    });

            Map<String, Object> result = service.cleanupRawArtifactsForCall(CALL_ID);

            assertThat(result).containsEntry("status", "CLEANED");
            assertThat((Long) result.get("deletedObjects")).isGreaterThan(0L);
            verify(s3Client, atLeastOnce()).deleteObjects(any(software.amazon.awssdk.services.s3.model.DeleteObjectsRequest.class));
        }

        @Test
        @DisplayName("private helpers cover bucket resolution and marker validation branches")
        void helperMethods_coverBucketAndPrefixLogic() {
            ReflectionTestUtils.setField(service, "defaultAwsRegion", Region.US_WEST_2);
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", null);
            ReflectionTestUtils.setField(service, "cachedAccountId", null);

            when(stsClient.getCallerIdentity()).thenReturn(GetCallerIdentityResponse.builder().account(ACCOUNT_ID).build());

            String bucket = ReflectionTestUtils.invokeMethod(service, "resolveOrCreateRecordingBucket");

            assertThat(bucket).isEqualTo("careconnect-recordings-" + ACCOUNT_ID + "-us-west-2");
            assertThat((Boolean) ReflectionTestUtils.invokeMethod(service, "isTopLevelPipelinePrefix", "12345678-1234-1234-1234-1234567890ab/"))
                    .isTrue();
            assertThat((Boolean) ReflectionTestUtils.invokeMethod(service, "isTopLevelPipelinePrefix", "recordings/"))
                    .isFalse();
        }

        @Test
        @DisplayName("private helper deleteObjectsUnderPrefix paginates across continuation tokens")
        void deleteObjectsUnderPrefix_paginatesAndCountsDeletes() {
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(
                            ListObjectsV2Response.builder()
                                    .contents(List.of(
                                            software.amazon.awssdk.services.s3.model.S3Object.builder().key("recordings/a").build(),
                                            software.amazon.awssdk.services.s3.model.S3Object.builder().key("recordings/b").build()))
                                    .isTruncated(true)
                                    .nextContinuationToken("next")
                                    .build(),
                            ListObjectsV2Response.builder()
                                    .contents(List.of(software.amazon.awssdk.services.s3.model.S3Object.builder().key("recordings/c").build()))
                                    .isTruncated(false)
                                    .build()
                    );

            Long deleted = ReflectionTestUtils.invokeMethod(service, "deleteObjectsUnderPrefix", BUCKET, "recordings/");

            assertThat(deleted).isEqualTo(3L);
            verify(s3Client, times(2)).deleteObjects(any(software.amazon.awssdk.services.s3.model.DeleteObjectsRequest.class));
        }
    }

    @Nested
    @DisplayName("recording bucket CORS (F1 / M7)")
    class RecordingBucketCorsTests {

        @Test
        @DisplayName("resolveOrCreateRecordingBucket applies GET/HEAD CORS with range expose headers")
        void resolveOrCreateRecordingBucket_appliesPlaybackCors() {
            ReflectionTestUtils.setField(service, "defaultAwsRegion", Region.US_EAST_1);
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", null);

            String bucket = ReflectionTestUtils.invokeMethod(service, "resolveOrCreateRecordingBucket");

            assertThat(bucket).isEqualTo("careconnect-recordings-" + ACCOUNT_ID + "-us-east-1");

            ArgumentCaptor<PutBucketCorsRequest> captor =
                    ArgumentCaptor.forClass(PutBucketCorsRequest.class);
            verify(s3Client).putBucketCors(captor.capture());

            CORSRule rule = captor.getValue().corsConfiguration().corsRules().get(0);
            assertThat(rule.allowedMethods()).containsExactlyInAnyOrder("GET", "HEAD");
            assertThat(rule.exposeHeaders())
                    .contains("Accept-Ranges", "Content-Range", "Content-Length", "ETag");
            assertThat(rule.allowedOrigins()).contains("*");
        }

        @Test
        @DisplayName("resolveOrCreateRecordingBucket uses explicit origins when wildcard disabled")
        void resolveOrCreateRecordingBucket_explicitOriginsWhenWildcardDisabled() {
            ReflectionTestUtils.setField(service, "defaultAwsRegion", Region.US_EAST_1);
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", null);
            ReflectionTestUtils.setField(service, "recordingCorsAllowWildcard", false);
            ReflectionTestUtils.setField(
                    service,
                    "corsAllowedOrigins",
                    "http://localhost:*,https://main.dpsx8p4n4v314.amplifyapp.com");

            ReflectionTestUtils.invokeMethod(service, "resolveOrCreateRecordingBucket");

            ArgumentCaptor<PutBucketCorsRequest> captor =
                    ArgumentCaptor.forClass(PutBucketCorsRequest.class);
            verify(s3Client).putBucketCors(captor.capture());

            CORSRule rule = captor.getValue().corsConfiguration().corsRules().get(0);
            assertThat(rule.allowedOrigins())
                    .containsExactly("https://main.dpsx8p4n4v314.amplifyapp.com");
            assertThat(rule.allowedOrigins()).doesNotContain("*");
        }
    }

    @Nested
    @DisplayName("recordingEnabled=false edge cases")
    class RecordingDisabledTests {

        @BeforeEach
        void disableRecording() {
            ReflectionTestUtils.setField(service, "recordingEnabled", false);
        }

        @Test
        @DisplayName("startRecording with disabled flag never touches ChimeService")
        void startRecording_disabled_noInteractionsWithChime() {
            service.startRecording(CALL_ID, USER_ID);
            verifyNoInteractions(chimeService);
        }

        @Test
        @DisplayName("startRecording returns DISABLED status map")
        void startRecording_disabled_statusIsDisabled() {
            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);
            assertThat(result.get("status")).isEqualTo("DISABLED");
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  initRecordingInfrastructure
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("initRecordingInfrastructure")
    class InitRecordingInfrastructureTests {

        @Test
        @DisplayName("does nothing when recordingEnabled is false")
        void initRecordingInfrastructure_disabled_doesNothing() {
            ReflectionTestUtils.setField(service, "recordingEnabled", false);

            service.initRecordingInfrastructure();

            verifyNoInteractions(iamClient);
        }

        @Test
        @DisplayName("does nothing when AWS is unavailable (pipelinesClient is null)")
        void initRecordingInfrastructure_awsUnavailable_doesNothing() {
            ReflectionTestUtils.setField(service, "pipelinesClient", null);

            service.initRecordingInfrastructure();

            verifyNoInteractions(iamClient);
        }

        @Test
        @DisplayName("provisions SLR and bucket when recording is enabled and AWS is available")
        void initRecordingInfrastructure_enabled_provisionsSLRAndBucket() {
            ReflectionTestUtils.setField(service, "recordingEnabled", true);

            service.initRecordingInfrastructure();

            verify(iamClient, atLeastOnce()).createServiceLinkedRole(any(
                    software.amazon.awssdk.services.iam.model.CreateServiceLinkedRoleRequest.class));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  reconcileCompletedRecordingCleanup
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("reconcileCompletedRecordingCleanup")
    class ReconcileCompletedRecordingCleanupTests {

        @Test
        @DisplayName("does nothing when recordingEnabled is false")
        void reconcile_disabled_doesNothing() {
            ReflectionTestUtils.setField(service, "recordingEnabled", false);

            service.reconcileCompletedRecordingCleanup();

            verifyNoInteractions(recordingRepository);
        }

        @Test
        @DisplayName("does nothing when rawCleanupEnabled is false")
        void reconcile_rawCleanupDisabled_doesNothing() {
            ReflectionTestUtils.setField(service, "rawCleanupEnabled", false);

            service.reconcileCompletedRecordingCleanup();

            verify(recordingRepository).findTop100ByStatusOrderByStartedAtDesc("STOP_RETRYABLE");
            verify(recordingRepository).findTop100ByStatusOrderByStartedAtDesc("FINALIZE_RETRYABLE");
            verify(recordingRepository, never()).findTop100ByStatusOrderByStartedAtDesc("STOPPED");
        }

        @Test
        @DisplayName("does nothing when s3Client is null")
        void reconcile_s3ClientNull_doesNothing() {
            ReflectionTestUtils.setField(service, "s3Client", null);

            service.reconcileCompletedRecordingCleanup();

            verify(recordingRepository).findTop100ByStatusOrderByStartedAtDesc("STOP_RETRYABLE");
            verify(recordingRepository).findTop100ByStatusOrderByStartedAtDesc("FINALIZE_RETRYABLE");
            verify(recordingRepository, never()).findTop100ByStatusOrderByStartedAtDesc("STOPPED");
        }

        @Test
        @DisplayName("processes stopped recordings from repository")
        void reconcile_stoppedRecordings_refreshesStatus() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("NOT_REQUESTED");

            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED"))
                    .thenReturn(List.of(rec));

            ListObjectsV2Response emptyListing = ListObjectsV2Response.builder()
                    .contents(Collections.emptyList())
                    .isTruncated(false)
                    .build();
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(emptyListing);

            service.reconcileCompletedRecordingCleanup();

            verify(recordingRepository).findTop100ByStatusOrderByStartedAtDesc("STOPPED");
        }

        @Test
        @DisplayName("handles exception during refresh gracefully")
        void reconcile_exceptionDuringRefresh_continuesWithoutThrowing() {
            CallRecording rec = buildRecording("STOPPED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationStatus("PROCESSING");
            rec.setConcatenationPipelineId("concat-pipe");

            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED"))
                    .thenReturn(List.of(rec));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenThrow(new RuntimeException("S3 error"));

            org.assertj.core.api.Assertions.assertThatCode(() -> service.reconcileCompletedRecordingCleanup())
                    .doesNotThrowAnyException();
        }

        @Test
        @DisplayName("skips null recordings in the list")
        void reconcile_nullRecordingInList_skips() {
            java.util.ArrayList<CallRecording> recordings = new java.util.ArrayList<>();
            recordings.add(null);

            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED"))
                    .thenReturn(recordings);

            org.assertj.core.api.Assertions.assertThatCode(() -> service.reconcileCompletedRecordingCleanup())
                    .doesNotThrowAnyException();
        }

        @Test
        @DisplayName("returns immediately when no stopped recordings exist")
        void reconcile_noStoppedRecordings_returnsImmediately() {
            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED"))
                    .thenReturn(Collections.emptyList());

            service.reconcileCompletedRecordingCleanup();

            verify(recordingRepository).findTop100ByStatusOrderByStartedAtDesc("STOPPED");
            verify(s3Client, never()).listObjectsV2(any(ListObjectsV2Request.class));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  stopRecording — additional edge cases
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("stopRecording — additional edge cases")
    class StopRecordingAdditionalTests {

        @Test
        @DisplayName("returns NOT_RECORDING when durable ownership is absent")
        void stopRecording_dbReturnsNullAfterPipelineRemoval_returnsNotRecording() {
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.empty());
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "NOT_RECORDING");
        }

        @Test
        @DisplayName("concatenation failure remains retryable when concatenation pipeline throws")
        void stopRecording_concatenationPipelineThrows_remainsRetryable() {
            CallRecording rec = buildRecording("STARTED");
            rec.setPipelineId(PIPELINE_ID);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);

            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));

            MediaCapturePipeline capturePipeline = MediaCapturePipeline.builder()
                    .mediaPipelineId(PIPELINE_ID)
                    .mediaPipelineArn("arn:aws:chime::" + ACCOUNT_ID + ":mediaPipeline/" + PIPELINE_ID)
                    .build();
            GetMediaCapturePipelineResponse getCapResp = GetMediaCapturePipelineResponse.builder()
                    .mediaCapturePipeline(capturePipeline)
                    .build();
            when(pipelinesClient.getMediaCapturePipeline(
                    any(GetMediaCapturePipelineRequest.class)))
                    .thenReturn(getCapResp);
            when(pipelinesClient.createMediaConcatenationPipeline(
                    any(CreateMediaConcatenationPipelineRequest.class)))
                    .thenThrow(new RuntimeException("Concatenation failed"));

            Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "RETRYABLE_FAILURE");
            assertThat(result).containsEntry("recordingStatus", "FINALIZE_RETRYABLE");
            assertThat(rec.getStatus()).isEqualTo("FINALIZE_RETRYABLE");
        }

        @Test
        @DisplayName("retry after deletion failure can complete stop and finalization")
        void stopRecording_retryAfterDeleteFailure_completes() {
            CallRecording rec = buildRecording("STARTED");
            rec.setPipelineId(PIPELINE_ID);
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaCapturePipeline(
                    any(GetMediaCapturePipelineRequest.class)))
                    .thenReturn(GetMediaCapturePipelineResponse.builder()
                            .mediaCapturePipeline(MediaCapturePipeline.builder()
                                    .mediaPipelineId(PIPELINE_ID)
                                    .mediaPipelineArn("arn:aws:chime:us-east-1:"
                                            + ACCOUNT_ID + ":media-pipeline/" + PIPELINE_ID)
                                    .build())
                            .build());
            when(pipelinesClient.deleteMediaCapturePipeline(
                            any(DeleteMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("temporary delete failure"))
                    .thenReturn(DeleteMediaCapturePipelineResponse.builder().build());
            when(pipelinesClient.createMediaConcatenationPipeline(
                    any(CreateMediaConcatenationPipelineRequest.class)))
                    .thenReturn(CreateMediaConcatenationPipelineResponse.builder()
                            .mediaConcatenationPipeline(MediaConcatenationPipeline.builder()
                                    .mediaPipelineId("concat-retry")
                                    .build())
                            .build());

            assertThat(service.stopRecording(CALL_ID))
                    .containsEntry("status", "RETRYABLE_FAILURE");
            assertThat(service.stopRecording(CALL_ID))
                    .containsEntry("status", "STOPPED");

            assertThat(rec.getStatus()).isEqualTo("STOPPED");
            verify(pipelinesClient, times(2)).deleteMediaCapturePipeline(
                    any(DeleteMediaCapturePipelineRequest.class));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  startRecording — additional edge cases
    // ══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("startRecording — additional edge cases")
    class StartRecordingAdditionalTests {

        @Test
        @DisplayName("returns ERROR when bucket resolution fails (STS returns null account)")
        void startRecording_bucketResolutionFails_returnsError() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", null);
            ReflectionTestUtils.setField(service, "cachedAccountId", null);
            ReflectionTestUtils.setField(service, "stsClient", null);

            Map<String, Object> result = service.startRecording(CALL_ID, USER_ID);

            assertThat(result).containsEntry("status", "ERROR");
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  Private helpers
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * Builds a minimal CallRecording for use in tests.
     */
    private CallRecording buildRecording(String status) {
        CallRecording rec = new CallRecording();
        rec.setId(1L);
        rec.setCallId(CALL_ID);
        rec.setPipelineId(PIPELINE_ID);
        rec.setStatus(status);
        rec.setInitiatedByUserId(USER_ID);
        rec.setStartedAt(LocalDateTime.now().minusMinutes(10));
        return rec;
    }
}
