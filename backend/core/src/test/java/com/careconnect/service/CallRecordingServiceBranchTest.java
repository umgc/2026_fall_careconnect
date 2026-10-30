package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallRecording;
import com.careconnect.model.PostCallTranscriptionJob;
import com.careconnect.model.RecordingLifecycleStatus;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.PostCallTranscriptionJobRepository;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import org.junit.jupiter.api.AfterEach;
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
import org.slf4j.LoggerFactory;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ChimeSdkMediaPipelinesException;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaCapturePipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaConcatenationPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaConcatenationPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaStreamPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaStreamPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaCapturePipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaConcatenationPipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineStatus;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaStreamPipeline;
import software.amazon.awssdk.services.iam.IamClient;
import software.amazon.awssdk.services.iam.model.CreateServiceLinkedRoleRequest;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.BucketAlreadyOwnedByYouException;
import software.amazon.awssdk.services.s3.model.CommonPrefix;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectsRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.ObjectIdentifier;
import software.amazon.awssdk.services.s3.model.PutBucketCorsRequest;
import software.amazon.awssdk.services.s3.model.PutBucketPolicyRequest;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityResponse;

/**
 * Branch-level unit tests for {@link CallRecordingService} that complement {@code
 * CallRecordingServiceTest}: start/stop ownership races, KVS ingest orchestration, concatenation
 * status refresh, raw-artifact cleanup and bucket provisioning failures.
 *
 * <p>Pure Mockito; every AWS client (Chime media pipelines, STS, S3, IAM) is a mock. S3 object
 * listings are served from a small in-memory key set.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("CallRecordingService branch coverage")
class CallRecordingServiceBranchTest {

    private static final String CALL_ID = "call-branch-1";
    private static final String MEETING_ID = "meeting-branch-1";
    private static final String PIPELINE_ID = "pipeline-branch-1";
    private static final String MSP_ID = "media-stream-pipeline-1";
    private static final String ACCOUNT_ID = "123456789012";
    private static final String BUCKET = "careconnect-recordings-123456789012-us-east-1";
    private static final String S3_PREFIX = "recordings/" + CALL_ID + "/20261001-100000/";
    private static final String CONCAT_ID = "concat-branch-1";
    private static final String PLAYABLE_KEY =
            S3_PREFIX + "concatenated/composited-video/" + CONCAT_ID + ".mp4";
    private static final String POOL_ARN =
            "arn:aws:chime:us-east-1:123456789012:media-pipeline-kinesis-video-stream-pool/dev";
    private static final long USER_ID = 7L;

    @Mock private ChimeSdkMediaPipelinesClient pipelinesClient;
    @Mock private StsClient stsClient;
    @Mock private S3Presigner s3Presigner;
    @Mock private S3Client s3Client;
    @Mock private IamClient iamClient;
    @Mock private ChimeService chimeService;
    @Mock private CallRecordingRepository recordingRepository;
    @Mock private CallAttendeeRepository callAttendeeRepository;
    @Mock private PostCallTranscriptionService postCallTranscriptionService;
    @Mock private RecordingCompensationWorker compensationWorker;
    @Mock private PostCallTranscriptionJobRepository transcriptionJobRepository;
    @Mock private KvsStreamPoolService kvsStreamPoolService;
    @Mock private KvsAttendeeStreamResolver kvsAttendeeStreamResolver;
    @Mock private KvsAttendeeStreamRegistry kvsAttendeeStreamRegistry;
    @Mock private CallAttendeeService callAttendeeService;

    @InjectMocks private CallRecordingService service;

    private final Logger serviceLogger = (Logger) LoggerFactory.getLogger(CallRecordingService.class);
    private Level originalLevel;

    /** In-memory S3 key set backing listObjectsV2/deleteObjects. */
    private final Set<String> s3Objects = new LinkedHashSet<>();
    /** Extra root-level common prefixes returned for delimiter listings. */
    private final List<String> extraRootPrefixes = new ArrayList<>();
    private boolean failRootListing;
    private String failExactKey;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.TRACE);

        ReflectionTestUtils.setField(service, "recordingEnabled", true);
        ReflectionTestUtils.setField(service, "presignedUrlTtlMinutes", 15);
        ReflectionTestUtils.setField(service, "rawCleanupEnabled", true);
        ReflectionTestUtils.setField(service, "corsAllowedOrigins", "http://localhost:*");
        ReflectionTestUtils.setField(service, "recordingCorsAllowWildcard", true);

        when(stsClient.getCallerIdentity())
                .thenReturn(GetCallerIdentityResponse.builder().account(ACCOUNT_ID).build());
        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class))).thenAnswer(inv -> list(inv.getArgument(0)));
        when(s3Client.deleteObjects(any(DeleteObjectsRequest.class)))
                .thenAnswer(
                        inv -> {
                            final DeleteObjectsRequest request = inv.getArgument(0);
                            request.delete().objects().stream()
                                    .map(ObjectIdentifier::key)
                                    .forEach(s3Objects::remove);
                            return null;
                        });
        when(kvsStreamPoolService.isIngestMode()).thenReturn(true);
        when(kvsStreamPoolService.isEnabled()).thenReturn(true);
        when(kvsStreamPoolService.getStreamPoolArn()).thenReturn(POOL_ARN);
    }

    @AfterEach
    void tearDown() {
        serviceLogger.setLevel(originalLevel);
        Thread.interrupted();
    }

    private ListObjectsV2Response list(final ListObjectsV2Request request) {
        if ("/".equals(request.delimiter())) {
            if (failRootListing) {
                throw new RuntimeException("root listing denied");
            }
            final Set<String> roots = new LinkedHashSet<>();
            for (final String key : s3Objects) {
                final int slash = key.indexOf('/');
                if (slash > 0) {
                    roots.add(key.substring(0, slash + 1));
                }
            }
            final List<CommonPrefix> prefixes = new ArrayList<>();
            roots.forEach(p -> prefixes.add(CommonPrefix.builder().prefix(p).build()));
            extraRootPrefixes.forEach(p -> prefixes.add(CommonPrefix.builder().prefix(p).build()));
            return ListObjectsV2Response.builder().commonPrefixes(prefixes).isTruncated(false).build();
        }
        final String prefix = request.prefix() == null ? "" : request.prefix();
        if (failExactKey != null && failExactKey.equals(prefix) && Integer.valueOf(1).equals(request.maxKeys())) {
            throw new RuntimeException("exact listing failed");
        }
        final List<S3Object> contents =
                s3Objects.stream()
                        .filter(k -> k.startsWith(prefix))
                        .map(k -> S3Object.builder().key(k).build())
                        .collect(Collectors.toList());
        return ListObjectsV2Response.builder().contents(contents).isTruncated(false).build();
    }

    private static CallRecording recording(final String status) {
        final CallRecording rec = new CallRecording();
        rec.setId(11L);
        rec.setCallId(CALL_ID);
        rec.setGeneration(1L);
        rec.setPipelineId(PIPELINE_ID);
        rec.setStatus(status);
        rec.setInitiatedByUserId(USER_ID);
        rec.setStartedAt(LocalDateTime.now(ZoneOffset.UTC).minusMinutes(5));
        return rec;
    }

    private static CallRecording stoppedWithLocation() {
        final CallRecording rec = recording("STOPPED");
        rec.setS3Bucket(BUCKET);
        rec.setS3Prefix(S3_PREFIX);
        rec.setConcatenationPipelineId(CONCAT_ID);
        return rec;
    }

    private static CallAttendee attendee(final String chimeId) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(chimeId);
        attendee.setJoinedAt(LocalDateTime.now());
        return attendee;
    }

    private static CreateMediaCapturePipelineResponse captureResponse() {
        return CreateMediaCapturePipelineResponse.builder()
                .mediaCapturePipeline(MediaCapturePipeline.builder().mediaPipelineId(PIPELINE_ID).build())
                .build();
    }

    private static GetMediaPipelineResponse concatStatus(final MediaPipelineStatus status) {
        return GetMediaPipelineResponse.builder()
                .mediaPipeline(
                        MediaPipeline.builder()
                                .mediaConcatenationPipeline(
                                        MediaConcatenationPipeline.builder().status(status).build())
                                .build())
                .build();
    }

    @SuppressWarnings("unchecked")
    private Map<String, String> activeMediaStreamPipelines() {
        return (Map<String, String>) ReflectionTestUtils.getField(service, "activeMediaStreamPipelineIds");
    }

    // ── startRecordingTyped ─────────────────────────────────────────────────

    @Nested
    @DisplayName("startRecordingTyped")
    class StartRecording {

        @Test
        @DisplayName("user playback without consent is policy blocked before any AWS call")
        void userWithoutConsent_policyBlocked() {
            final RecordingStartResult result = service.startRecordingTyped(CALL_ID, USER_ID, false);

            assertThat(result.status()).isEqualTo(RecordingStartResult.Status.POLICY_BLOCKED);
            verify(chimeService, never()).getMeetingId(anyString());
        }

        @Test
        @DisplayName("another node's active capture blocks a user start and reports to a system start")
        void notReservedActiveCapture_blocksUserStart() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            final CallRecording active = recording("STARTED");
            active.setLifecycleStatus(RecordingLifecycleStatus.ACTIVE);
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(active));
            when(recordingRepository.reserveActiveGeneration(anyString(), anyString(), any(), anyBoolean()))
                    .thenReturn(0);

            assertThat(service.startRecordingTyped(CALL_ID, USER_ID, true).status())
                    .isEqualTo(RecordingStartResult.Status.POLICY_BLOCKED);
        }

        @Test
        @DisplayName("an active row after a fresh reservation blocks users and reports to the system")
        void reservedButActiveRow_reportsAlreadyActive() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            final CallRecording active = recording("STARTED");
            active.setLifecycleStatus(RecordingLifecycleStatus.ACTIVE);
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(active));
            when(recordingRepository.reserveActiveGeneration(anyString(), anyString(), any(), anyBoolean()))
                    .thenReturn(1);

            assertThat(service.startRecordingTyped(CALL_ID, USER_ID, true).status())
                    .isEqualTo(RecordingStartResult.Status.POLICY_BLOCKED);
            assertThat(service.startRecordingTyped(CALL_ID, null, false).status())
                    .isEqualTo(RecordingStartResult.Status.ALREADY_RECORDING);
        }

        @Test
        @DisplayName("an unresolvable account id after the bucket is cached returns ERROR")
        void accountIdUnavailable_returnsError() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", BUCKET);
            when(stsClient.getCallerIdentity()).thenThrow(new RuntimeException("sts down"));

            final RecordingStartResult result = service.startRecordingTyped(CALL_ID, null, false);

            assertThat(result.status()).isEqualTo(RecordingStartResult.Status.ERROR);
            assertThat(result.message()).contains("account ID");
        }

        @Test
        @DisplayName("a consented reserved row is stamped with consent and started")
        void reservedRowWithoutConsent_isStampedAndStarted() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            final CallRecording reserved = recording(null);
            reserved.setLifecycleStatus(RecordingLifecycleStatus.RESERVED);
            reserved.setConsentedAt(null);
            when(recordingRepository.reserveActiveGeneration(anyString(), anyString(), any(), anyBoolean()))
                    .thenReturn(1);
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(reserved));
            when(pipelinesClient.createMediaCapturePipeline(any(CreateMediaCapturePipelineRequest.class)))
                    .thenReturn(captureResponse());
            ReflectionTestUtils.setField(service, "defaultAwsRegion", Region.US_WEST_2);

            final RecordingStartResult result = service.startRecordingTyped(CALL_ID, USER_ID, true);

            assertThat(result.status()).isEqualTo(RecordingStartResult.Status.STARTED);
            assertThat(reserved.getConsentedAt()).isNotNull();
            assertThat(reserved.getConsentedByUserId()).isEqualTo(USER_ID);
            final ArgumentCaptor<CreateBucketRequest> bucket = ArgumentCaptor.forClass(CreateBucketRequest.class);
            verify(s3Client).createBucket(bucket.capture());
            assertThat(bucket.getValue().createBucketConfiguration().locationConstraintAsString())
                    .isEqualTo("us-west-2");
        }

        @Test
        @DisplayName("a persistence failure after AWS start enqueues compensation and returns ERROR")
        void saveFailure_enqueuesCompensation() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(pipelinesClient.createMediaCapturePipeline(any(CreateMediaCapturePipelineRequest.class)))
                    .thenReturn(captureResponse());
            when(recordingRepository.saveAndFlush(any(CallRecording.class)))
                    .thenThrow(new RuntimeException("db down"));
            when(recordingRepository.save(any(CallRecording.class))).thenThrow(new RuntimeException("db down"));

            final RecordingStartResult result = service.startRecordingTyped(CALL_ID, null, false);

            assertThat(result.status()).isEqualTo(RecordingStartResult.Status.ERROR);
            verify(compensationWorker)
                    .enqueueCapture(eq(CALL_ID), eq(1L), eq(PIPELINE_ID), eq(BUCKET), anyString());
        }

        @Test
        @DisplayName("without a compensation worker the persistence failure is only logged")
        void saveFailure_withoutWorker_returnsError() {
            ReflectionTestUtils.setField(service, "compensationWorker", null);
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(pipelinesClient.createMediaCapturePipeline(any(CreateMediaCapturePipelineRequest.class)))
                    .thenReturn(captureResponse());
            when(recordingRepository.saveAndFlush(any(CallRecording.class)))
                    .thenThrow(new RuntimeException("db down"));

            assertThat(service.startRecordingTyped(CALL_ID, null, false).status())
                    .isEqualTo(RecordingStartResult.Status.ERROR);
        }

        @Test
        @DisplayName("a service-linked-role propagation error is retried once")
        void slrPropagationError_retriesOnce() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(pipelinesClient.createMediaCapturePipeline(any(CreateMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("Create a service-linked role first"))
                    .thenReturn(captureResponse());
            // Pre-set the interrupt flag so the 5s back-off returns immediately.
            Thread.currentThread().interrupt();

            final RecordingStartResult result = service.startRecordingTyped(CALL_ID, null, false);

            assertThat(Thread.interrupted()).isTrue();
            assertThat(result.status()).isEqualTo(RecordingStartResult.Status.STARTED);
            verify(pipelinesClient, times(2))
                    .createMediaCapturePipeline(any(CreateMediaCapturePipelineRequest.class));
        }
    }

    // ── infrastructure provisioning ─────────────────────────────────────────

    @Nested
    @DisplayName("initRecordingInfrastructure")
    class Provisioning {

        @Test
        @DisplayName("tolerates bucket-already-owned, policy, CORS and SLR failures")
        void provisioningFailures_areTolerated() {
            when(s3Client.createBucket(any(CreateBucketRequest.class)))
                    .thenThrow(BucketAlreadyOwnedByYouException.builder().message("owned").build());
            when(s3Client.putBucketPolicy(any(PutBucketPolicyRequest.class)))
                    .thenThrow(new RuntimeException("policy denied"));
            when(s3Client.putBucketCors(any(PutBucketCorsRequest.class)))
                    .thenThrow(new RuntimeException("cors denied"));
            when(iamClient.createServiceLinkedRole(any(CreateServiceLinkedRoleRequest.class)))
                    .thenThrow(new RuntimeException("Role name has been taken"))
                    .thenThrow(new RuntimeException("User is not authorized"))
                    .thenThrow(new RuntimeException("unexpected"))
                    .thenThrow(new RuntimeException((String) null));

            service.initRecordingInfrastructure();
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", null);
            service.initRecordingInfrastructure();

            assertThat(ReflectionTestUtils.getField(service, "cachedRecordingBucket")).isEqualTo(BUCKET);
            verify(iamClient, times(4)).createServiceLinkedRole(any(CreateServiceLinkedRoleRequest.class));
        }

        @Test
        @DisplayName("a generic createBucket failure still applies policy and CORS")
        void createBucketGenericFailure_continues() {
            when(s3Client.createBucket(any(CreateBucketRequest.class)))
                    .thenThrow(new RuntimeException("throttled"));
            ReflectionTestUtils.setField(service, "iamClient", null);

            service.initRecordingInfrastructure();

            verify(s3Client).putBucketPolicy(any(PutBucketPolicyRequest.class));
            verify(s3Client).putBucketCors(any(PutBucketCorsRequest.class));
        }

        @Test
        @DisplayName("missing STS client leaves the bucket unresolved")
        void missingSts_leavesBucketUnresolved() {
            ReflectionTestUtils.setField(service, "stsClient", null);

            service.initRecordingInfrastructure();

            assertThat(ReflectionTestUtils.getField(service, "cachedRecordingBucket")).isNull();
            verify(s3Client, never()).createBucket(any(CreateBucketRequest.class));
        }

        @Test
        @DisplayName("blank CORS config allows any origin")
        void blankCors_allowsAnyOrigin() {
            ReflectionTestUtils.setField(service, "corsAllowedOrigins", " ");

            service.initRecordingInfrastructure();

            final ArgumentCaptor<PutBucketCorsRequest> captor = ArgumentCaptor.forClass(PutBucketCorsRequest.class);
            verify(s3Client).putBucketCors(captor.capture());
            assertThat(captor.getValue().corsConfiguration().corsRules().get(0).allowedOrigins())
                    .containsExactly("*");
        }

        @Test
        @DisplayName("explicit origins skip blank entries")
        void explicitOrigins_skipBlankEntries() {
            ReflectionTestUtils.setField(service, "corsAllowedOrigins", "https://a.example, ,https://b.example");

            service.initRecordingInfrastructure();

            final ArgumentCaptor<PutBucketCorsRequest> captor = ArgumentCaptor.forClass(PutBucketCorsRequest.class);
            verify(s3Client).putBucketCors(captor.capture());
            assertThat(captor.getValue().corsConfiguration().corsRules().get(0).allowedOrigins())
                    .containsExactly("https://a.example", "https://b.example");
        }

        @Test
        @DisplayName("wildcard-only origins with wildcard disallowed yield no origins")
        void wildcardDisallowed_yieldsNoOrigins() {
            ReflectionTestUtils.setField(service, "recordingCorsAllowWildcard", false);

            service.initRecordingInfrastructure();

            final ArgumentCaptor<PutBucketCorsRequest> captor = ArgumentCaptor.forClass(PutBucketCorsRequest.class);
            verify(s3Client).putBucketCors(captor.capture());
            assertThat(captor.getValue().corsConfiguration().corsRules().get(0).allowedOrigins()).isEmpty();
        }
    }

    // ── stopRecording ───────────────────────────────────────────────────────

    @Nested
    @DisplayName("stopRecording")
    class StopRecording {

        @Test
        @DisplayName("no active recording still stops a live media stream pipeline")
        void noRecording_stopsMediaStream() {
            activeMediaStreamPipelines().put(CALL_ID, MSP_ID);

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "NOT_RECORDING");
            verify(pipelinesClient).deleteMediaPipeline(any(DeleteMediaPipelineRequest.class));
        }

        @Test
        @DisplayName("a recording without any pipeline id is reported as not recording")
        void recordingWithoutPipelineId_notRecording() {
            final CallRecording rec = recording("STARTED");
            rec.setPipelineId(null);
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(rec));

            assertThat(service.stopRecording(CALL_ID)).containsEntry("status", "NOT_RECORDING");
        }

        @Test
        @DisplayName("a stop lease owned by another worker returns a retryable failure")
        void leaseOwnedElsewhere_retryable() {
            final CallRecording rec = recording("STARTED");
            rec.setLifecycleStatus(RecordingLifecycleStatus.ACTIVE);
            final CallRecording owner = recording("STARTED");
            owner.setClaimToken(UUID.randomUUID());
            when(recordingRepository.findActiveByCallId(CALL_ID))
                    .thenReturn(Optional.of(rec))
                    .thenReturn(Optional.of(owner));
            when(recordingRepository.claimForStop(anyLong(), any(UUID.class), anyLong())).thenReturn(0);

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "RETRYABLE_FAILURE");
            assertThat(result.get("message").toString()).contains("Another worker");
        }

        @Test
        @DisplayName("a blank pipeline id cannot resolve a capture ARN and stays retryable")
        void blankPipelineId_retryable() {
            final CallRecording rec = recording("STARTED");
            rec.setPipelineId(" ");
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(rec));

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "RETRYABLE_FAILURE");
            assertThat(rec.getStatus()).isEqualTo("STOP_RETRYABLE");
        }

        @Test
        @DisplayName("a 404 on capture delete is ignored and concatenation starts for a blank id")
        void deleteNotFound_startsConcatenation() {
            final CallRecording rec = recording("STARTED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            rec.setConcatenationPipelineId(" ");
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaCapturePipeline(any(GetMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("get failed"));
            when(pipelinesClient.deleteMediaCapturePipeline(any(DeleteMediaCapturePipelineRequest.class)))
                    .thenThrow(
                            (ChimeSdkMediaPipelinesException)
                                    ChimeSdkMediaPipelinesException.builder()
                                            .statusCode(404)
                                            .message("gone")
                                            .build());
            when(pipelinesClient.createMediaConcatenationPipeline(
                            any(CreateMediaConcatenationPipelineRequest.class)))
                    .thenReturn(
                            CreateMediaConcatenationPipelineResponse.builder()
                                    .mediaConcatenationPipeline(
                                            MediaConcatenationPipeline.builder()
                                                    .mediaPipelineId(CONCAT_ID)
                                                    .build())
                                    .build());

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result)
                    .containsEntry("status", "STOPPED")
                    .containsEntry("concatenationPipelineId", CONCAT_ID);
        }

        @Test
        @DisplayName("an existing concatenation id is reused and a non-pending status is not finalized")
        void existingConcatenation_reused() {
            final CallRecording rec = recording("UNKNOWN");
            rec.setConcatenationPipelineId(CONCAT_ID);
            rec.setConcatenationStatus("PROCESSING");
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaCapturePipeline(any(GetMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("get failed"));

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result)
                    .containsEntry("status", "STOPPED")
                    .containsEntry("concatenationPipelineId", CONCAT_ID)
                    .containsEntry("concatenationStatus", "PROCESSING");
            assertThat(rec.getStatus()).isEqualTo("UNKNOWN");
        }
    }

    // ── media stream pipeline (KVS ingest) ──────────────────────────────────

    @Nested
    @DisplayName("media stream pipeline")
    class MediaStreamPipelineTests {

        @Test
        @DisplayName("startMediaStreamPipeline reports missing meeting, AWS, attendees and account")
        void startMediaStreamPipeline_guardFailures() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(null);
            assertThat(service.startMediaStreamPipeline(CALL_ID)).containsEntry("status", "ERROR");

            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            ReflectionTestUtils.setField(service, "pipelinesClient", null);
            assertThat(service.startMediaStreamPipeline(CALL_ID)).containsEntry("status", "UNAVAILABLE");

            ReflectionTestUtils.setField(service, "pipelinesClient", pipelinesClient);
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(List.of());
            assertThat(service.startMediaStreamPipeline(CALL_ID).get("message").toString())
                    .contains("No active call attendees");

            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                    .thenReturn(List.of(attendee("a1")));
            when(stsClient.getCallerIdentity()).thenThrow(new RuntimeException("sts down"));
            assertThat(service.startMediaStreamPipeline(CALL_ID).get("message").toString())
                    .contains("account ID");
        }

        @Test
        @DisplayName("a pending in-flight claim reports IN_PROGRESS")
        void pendingClaim_inProgress() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                    .thenReturn(List.of(attendee("a1")));
            activeMediaStreamPipelines().put(CALL_ID, "__pending__");

            assertThat(service.startMediaStreamPipeline(CALL_ID)).containsEntry("status", "IN_PROGRESS");
        }

        @Test
        @DisplayName("a CreateMediaStreamPipeline failure releases the claim and reports ERROR")
        void createFailure_releasesClaim() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                    .thenReturn(List.of(attendee("a1")));
            when(pipelinesClient.createMediaStreamPipeline(any(CreateMediaStreamPipelineRequest.class)))
                    .thenThrow(new RuntimeException("limit exceeded"));

            final Map<String, Object> result = service.startMediaStreamPipeline(CALL_ID);

            assertThat(result).containsEntry("status", "ERROR");
            assertThat(activeMediaStreamPipelines()).doesNotContainKey(CALL_ID);
        }

        @Test
        @DisplayName("stopMediaStreamPipeline resolves a pending claim from the DB and tolerates delete failure")
        void stopMediaStream_pendingClaimAndDeleteFailure() {
            activeMediaStreamPipelines().put(CALL_ID, "__pending__");
            final CallRecording rec = recording("STOPPED");
            rec.setMediaStreamPipelineId(MSP_ID);
            when(recordingRepository.findTopByCallIdAndInitiatedByUserIdIsNullOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(rec));
            when(pipelinesClient.deleteMediaPipeline(any(DeleteMediaPipelineRequest.class)))
                    .thenThrow(new RuntimeException("delete failed"));

            final Map<String, Object> result = service.stopMediaStreamPipeline(CALL_ID);

            assertThat(result)
                    .containsEntry("status", "STOPPED")
                    .containsEntry("mediaStreamPipelineId", MSP_ID)
                    .containsEntry("warning", "delete failed");
            assertThat(rec.getMediaStreamPipelineId()).isNull();
        }

        @Test
        @DisplayName("stopMediaStreamPipeline without AWS only clears local state")
        void stopMediaStream_withoutAws() {
            activeMediaStreamPipelines().put(CALL_ID, MSP_ID);
            ReflectionTestUtils.setField(service, "pipelinesClient", null);

            assertThat(service.stopMediaStreamPipeline(CALL_ID))
                    .containsEntry("status", "STOPPED")
                    .containsEntry("mediaStreamPipelineId", MSP_ID);
        }
    }

    // ── startKvsPipeline / async wrappers ───────────────────────────────────

    @Nested
    @DisplayName("startKvsPipeline")
    class KvsPipeline {

        private void stubStreamStart() {
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(pipelinesClient.createMediaStreamPipeline(any(CreateMediaStreamPipelineRequest.class)))
                    .thenReturn(
                            CreateMediaStreamPipelineResponse.builder()
                                    .mediaStreamPipeline(
                                            MediaStreamPipeline.builder().mediaPipelineId(MSP_ID).build())
                                    .build());
        }

        @Test
        @DisplayName("starts ingest and persists every attendee stream")
        void start_success() {
            stubStreamStart();
            final List<CallAttendee> attendees = List.of(attendee("a1"));
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(attendees);
            when(kvsAttendeeStreamResolver.resolve(CALL_ID, attendees, MSP_ID, MEETING_ID))
                    .thenReturn(Map.of("a1", "arn:stream/a1"));
            final CallRecording rec = recording("STARTED");
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));

            final Map<String, Object> result = service.startKvsPipeline(CALL_ID);

            assertThat(result).containsEntry("status", "STARTED").containsEntry("attendeeStreamCount", 1);
            verify(callAttendeeService).reconcileRosterFromChime(CALL_ID, MEETING_ID);
            verify(callAttendeeService).recordKvsStreamMapping(CALL_ID, "a1", "arn:stream/a1");
        }

        @Test
        @DisplayName("an attendee without a resolved stream stops ingest and reports ERROR")
        void unresolvedAttendee_stopsIngest() {
            stubStreamStart();
            final List<CallAttendee> attendees = List.of(attendee("a1"));
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(attendees);
            when(kvsAttendeeStreamResolver.resolve(CALL_ID, attendees, MSP_ID, MEETING_ID))
                    .thenReturn(Map.of("a1", " "));

            final Map<String, Object> result = service.startKvsPipeline(CALL_ID);

            assertThat(result).containsEntry("status", "ERROR");
            assertThat(result.get("message").toString()).contains("No KVS stream assigned");
            verify(pipelinesClient).deleteMediaPipeline(any(DeleteMediaPipelineRequest.class));
        }

        @Test
        @DisplayName("an empty roster at resolution time stops ingest and reports ERROR")
        void emptyRosterAtResolution_stopsIngest() {
            stubStreamStart();
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                    .thenReturn(List.of(attendee("a1")))
                    .thenReturn(List.of());
            when(kvsAttendeeStreamResolver.resolve(eq(CALL_ID), any(), eq(MSP_ID), eq(MEETING_ID)))
                    .thenReturn(Map.of());

            final Map<String, Object> result = service.startKvsPipeline(CALL_ID);

            assertThat(result.get("message").toString()).contains("KVS stream assignment");
        }

        @Test
        @DisplayName("an existing pipeline whose stream refresh fails still reports ALREADY_STARTED")
        void existingPipeline_refreshFailure() {
            final CallRecording rec = recording("STARTED");
            rec.setMediaStreamPipelineId(MSP_ID);
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                    .thenThrow(new RuntimeException("db down"));

            assertThat(service.startKvsPipeline(CALL_ID))
                    .containsEntry("status", "ALREADY_STARTED")
                    .containsEntry("mediaStreamPipelineId", MSP_ID);
        }

        @Test
        @DisplayName("pending claim, missing meeting, missing AWS and ingest errors short-circuit")
        void guardPaths() {
            activeMediaStreamPipelines().put(CALL_ID, "__pending__");
            assertThat(service.startKvsPipeline(CALL_ID)).containsEntry("status", "IN_PROGRESS");
            activeMediaStreamPipelines().clear();

            when(chimeService.getMeetingId(CALL_ID)).thenReturn(null);
            assertThat(service.startKvsPipeline(CALL_ID)).containsEntry("status", "ERROR");

            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            ReflectionTestUtils.setField(service, "pipelinesClient", null);
            assertThat(service.startKvsPipeline(CALL_ID)).containsEntry("status", "UNAVAILABLE");

            ReflectionTestUtils.setField(service, "pipelinesClient", pipelinesClient);
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(List.of());
            assertThat(service.startKvsPipeline(CALL_ID).get("message").toString())
                    .contains("No active call attendees");
        }

        @Test
        @DisplayName("async start logs success, non-success and exceptions without throwing")
        void asyncStart_allOutcomes() {
            stubStreamStart();
            final List<CallAttendee> attendees = List.of(attendee("a1"));
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(attendees);
            when(kvsAttendeeStreamResolver.resolve(CALL_ID, attendees, MSP_ID, MEETING_ID))
                    .thenReturn(Map.of("a1", "arn:stream/a1"));
            service.startKvsPipelineAsync(CALL_ID);
            assertThat(activeMediaStreamPipelines()).containsEntry(CALL_ID, MSP_ID);

            activeMediaStreamPipelines().clear();
            when(chimeService.getMeetingId("other-call")).thenReturn(null);
            service.startKvsPipelineAsync("other-call");

            when(kvsStreamPoolService.isEnabled()).thenThrow(new RuntimeException("config error"));
            service.startKvsPipelineAsync("third-call");
            verify(chimeService, never()).getMeetingId("third-call");
        }

        @Test
        @DisplayName("async refresh skips when disabled, unstarted or meeting missing and swallows failures")
        void asyncRefresh_allOutcomes() {
            when(kvsStreamPoolService.isIngestMode()).thenReturn(false);
            service.refreshKvsAttendeeStreamsAsync(CALL_ID);
            verify(recordingRepository, never()).findTopByCallIdOrderByStartedAtDesc(CALL_ID);

            when(kvsStreamPoolService.isIngestMode()).thenReturn(true);
            service.refreshKvsAttendeeStreamsAsync(CALL_ID);
            verify(chimeService, never()).getMeetingId(CALL_ID);

            activeMediaStreamPipelines().put(CALL_ID, MSP_ID);
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(null);
            service.refreshKvsAttendeeStreamsAsync(CALL_ID);
            verify(kvsAttendeeStreamResolver, never()).resolve(anyString(), any(), anyString(), anyString());

            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);
            final List<CallAttendee> attendees = List.of(attendee("a1"));
            when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(attendees);
            when(kvsAttendeeStreamResolver.resolve(CALL_ID, attendees, MSP_ID, MEETING_ID))
                    .thenReturn(Map.of("a1", "arn:stream/a1"))
                    .thenThrow(new IllegalStateException("timed out"));
            service.refreshKvsAttendeeStreamsAsync(CALL_ID);
            service.refreshKvsAttendeeStreamsAsync(CALL_ID);
            verify(callAttendeeService).recordKvsStreamMapping(CALL_ID, "a1", "arn:stream/a1");
        }
    }

    // ── status refresh, playback and cleanup ────────────────────────────────

    @Nested
    @DisplayName("status refresh and cleanup")
    class RefreshAndCleanup {

        @Test
        @DisplayName("live capture status failure is ignored in the status response")
        void liveStatusFailure_ignored() {
            final CallRecording rec = recording("STARTED");
            rec.setLifecycleStatus(RecordingLifecycleStatus.ACTIVE);
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaCapturePipeline(any(GetMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("throttled"));

            final Map<String, Object> result = service.getRecordingStatus(CALL_ID);

            assertThat(result).doesNotContainKey("liveStatus");
        }

        @Test
        @DisplayName("concatenation status maps STOPPED, IN_PROGRESS, missing pipeline and errors to PROCESSING")
        void concatenationStatusVariants() {
            final CallRecording rec = stoppedWithLocation();
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaPipeline(any(GetMediaPipelineRequest.class)))
                    .thenReturn(concatStatus(MediaPipelineStatus.STOPPED))
                    .thenReturn(concatStatus(MediaPipelineStatus.IN_PROGRESS))
                    .thenReturn(GetMediaPipelineResponse.builder().build())
                    .thenThrow(new RuntimeException("throttled"));

            for (int i = 0; i < 4; i++) {
                rec.setConcatenationStatus(null);
                service.getRecordingStatus(CALL_ID);
                assertThat(rec.getConcatenationStatus()).isEqualTo("PROCESSING");
            }

            ReflectionTestUtils.setField(service, "pipelinesClient", null);
            rec.setConcatenationStatus(null);
            service.getRecordingStatus(CALL_ID);
            assertThat(rec.getConcatenationStatus()).isEqualTo("PROCESSING");
            rec.setConcatenationStatus("FAILED");
            service.getRecordingStatus(CALL_ID);
            assertThat(rec.getConcatenationStatus()).isEqualTo("FAILED");
        }

        @Test
        @DisplayName("playback for a failed stitch explains the failure")
        void playbackFailedStitch_message() {
            final CallRecording rec = stoppedWithLocation();
            rec.setConcatenationStatus("FAILED");
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.getMediaPipeline(any(GetMediaPipelineRequest.class)))
                    .thenReturn(concatStatus(MediaPipelineStatus.FAILED));

            final Map<String, Object> result = service.generatePlaybackUrl(CALL_ID);

            assertThat(result).containsEntry("status", "PROCESSING");
            assertThat(result.get("message").toString()).contains("did not complete");
        }

        @Test
        @DisplayName("a ready stitch clears the stale missing-output error and triggers late transcription")
        void readyStitch_clearsErrorAndTriggersLateTranscription() {
            final CallRecording rec = stoppedWithLocation();
            rec.setConcatenationStatus("READY");
            rec.setEndedAt(LocalDateTime.now(ZoneOffset.UTC).minusMinutes(1));
            rec.setErrorMessage("Concatenation pipeline completed but no stitched video was found under x");
            s3Objects.add(PLAYABLE_KEY);
            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED")).thenReturn(List.of(rec));

            service.reconcileCompletedRecordingCleanup();

            assertThat(rec.getErrorMessage()).isNull();
            verify(postCallTranscriptionService).transcribeAndCleanup(CALL_ID, rec, PLAYABLE_KEY);
        }

        @Test
        @DisplayName("late transcription is not re-triggered when processing, complete, undated or stale")
        void readyStitch_noLateTriggerWhenNotEligible() {
            s3Objects.add(PLAYABLE_KEY);
            final CallRecording processing = stoppedWithLocation();
            processing.setConcatenationStatus("READY");
            processing.setTranscriptionStatus(PostCallTranscriptionService.TRANSCRIPTION_STATUS_PROCESSING);
            final CallRecording undated = stoppedWithLocation();
            undated.setConcatenationStatus("READY");
            undated.setStartedAt(null);
            final CallRecording stale = stoppedWithLocation();
            stale.setConcatenationStatus("READY");
            stale.setEndedAt(LocalDateTime.now(ZoneOffset.UTC).minusHours(3));
            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED"))
                    .thenReturn(Arrays.asList(processing, null, undated, stale));

            service.reconcileCompletedRecordingCleanup();

            verify(postCallTranscriptionService, never()).transcribeAndCleanup(anyString(), any(), anyString());
        }

        @Test
        @DisplayName("reconcile retries pending stops and survives stop and refresh failures")
        void reconcile_retriesPendingStops() {
            final CallRecording noCall = recording("STOP_RETRYABLE");
            noCall.setCallId(null);
            final CallRecording retry = recording("STOP_RETRYABLE");
            retry.setCallId("retry-call");
            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOP_RETRYABLE"))
                    .thenReturn(Arrays.asList(null, noCall, retry));
            when(recordingRepository.findActiveByCallId("retry-call"))
                    .thenThrow(new RuntimeException("db down"));
            final CallRecording broken = stoppedWithLocation();
            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED")).thenReturn(List.of(broken));
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenThrow(new RuntimeException("s3 down"));

            service.reconcileCompletedRecordingCleanup();

            verify(recordingRepository).findActiveByCallId("retry-call");
        }

        @Test
        @DisplayName("cleanup deletes raw artifacts, skips prefixes holding the final video and clears empty markers")
        void cleanup_deletesRawArtifacts() {
            final String topLevel = "0123456789abcdef0123456789abcdef/";
            final String emptyMarker = "fedcba9876543210fedcba9876543210/";
            final CallRecording rec = stoppedWithLocation();
            // pipelineId "recordings" makes a non-managed prefix that contains the playable key.
            rec.setPipelineId("recordings");
            s3Objects.addAll(
                    List.of(
                            PLAYABLE_KEY,
                            S3_PREFIX + "audio/a.wav",
                            S3_PREFIX + "video/v.mp4",
                            topLevel + "video/x-" + CONCAT_ID + ".mp4",
                            emptyMarker,
                            "plainfolder/file.txt"));
            extraRootPrefixes.addAll(Arrays.asList("a/b/", " ", null));
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));

            final Map<String, Object> result = service.cleanupRawArtifactsForCall(CALL_ID);

            assertThat(result).containsEntry("status", "CLEANED");
            assertThat((Long) result.get("deletedObjects")).isGreaterThanOrEqualTo(3L);
            assertThat(s3Objects)
                    .contains(PLAYABLE_KEY, "plainfolder/file.txt")
                    .doesNotContain(S3_PREFIX + "audio/a.wav", topLevel + "video/x-" + CONCAT_ID + ".mp4", emptyMarker);
        }

        @Test
        @DisplayName("cleanup with nothing to delete and failing root and exact listings still completes")
        void cleanup_nothingDeletedAndListingFailures() {
            final CallRecording rec = stoppedWithLocation();
            rec.setPipelineId("/");
            s3Objects.add(PLAYABLE_KEY);
            failRootListing = true;
            failExactKey = "/";
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));

            final Map<String, Object> result = service.cleanupRawArtifactsForCall(CALL_ID);

            assertThat(result).containsEntry("status", "CLEANED").containsEntry("deletedObjects", 0L);
        }
    }

    // ── purge ───────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("purge")
    class Purge {

        @Test
        @DisplayName("purgeAllRecordings is pending while a capture or transcription is active")
        void purgeAll_pendingWhileActive() {
            final CallRecording active = recording("STARTED");
            active.setLifecycleStatus(RecordingLifecycleStatus.ACTIVE);
            final CallRecording transcribing = recording("STOPPED");
            transcribing.setId(12L);
            transcribing.setLifecycleStatus(RecordingLifecycleStatus.COMPLETE);
            final PostCallTranscriptionJob job = new PostCallTranscriptionJob();
            job.setState("PENDING");
            when(transcriptionJobRepository.findByRecordingId(12L)).thenReturn(Optional.of(job));
            when(recordingRepository.findAll()).thenReturn(List.of(active, transcribing));

            final Map<String, Object> result = service.purgeAllRecordings();

            assertThat(result).containsEntry("status", "PENDING").containsEntry("activeRecordings", 2);
            verify(recordingRepository, never()).deleteAll();
        }

        @Test
        @DisplayName("purgeAllRecordings follows continuation tokens and tolerates S3 failure")
        void purgeAll_paginatesAndToleratesFailure() {
            ReflectionTestUtils.setField(service, "cachedRecordingBucket", BUCKET);
            final CallRecording done = recording("STOPPED");
            done.setLifecycleStatus(RecordingLifecycleStatus.FAILED);
            final PostCallTranscriptionJob job = new PostCallTranscriptionJob();
            job.setState("COMPLETE");
            when(transcriptionJobRepository.findByRecordingId(11L)).thenReturn(Optional.of(job));
            when(recordingRepository.findAll()).thenReturn(List.of(done));
            when(recordingRepository.count()).thenReturn(1L);
            when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                    .thenReturn(
                            ListObjectsV2Response.builder()
                                    .contents(S3Object.builder().key("recordings/a").build())
                                    .isTruncated(true)
                                    .nextContinuationToken("next")
                                    .build())
                    .thenReturn(
                            ListObjectsV2Response.builder()
                                    .contents(S3Object.builder().key("recordings/b").build())
                                    .isTruncated(false)
                                    .build())
                    .thenThrow(new RuntimeException("s3 down"));

            final Map<String, Object> first = service.purgeAllRecordings();
            final Map<String, Object> second = service.purgeAllRecordings();

            assertThat(first).containsEntry("deletedS3Objects", 2L);
            assertThat(second).containsEntry("deletedS3Objects", 0L);
            final ArgumentCaptor<ListObjectsV2Request> captor = ArgumentCaptor.forClass(ListObjectsV2Request.class);
            verify(s3Client, times(3)).listObjectsV2(captor.capture());
            assertThat(captor.getAllValues().get(1).continuationToken()).isEqualTo("next");
        }

        @Test
        @DisplayName("purgeRecordingsForCall marks active captures purge-pending and stops them")
        void purgeForCall_activeCapture() {
            final CallRecording active = recording("STARTED");
            active.setLifecycleStatus(RecordingLifecycleStatus.ACTIVE);
            when(recordingRepository.findByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(List.of(active));

            final Map<String, Object> result = service.purgeRecordingsForCall(" " + CALL_ID + " ");

            assertThat(result).containsEntry("status", "PENDING");
            assertThat(active.getPurgeRequestedAt()).isNotNull();
            verify(recordingRepository, never()).deleteByCallId(anyString());
        }

        @Test
        @DisplayName("purgeRecordingsForCall waits for transcription and skips rows without S3 bucket")
        void purgeForCall_pendingTranscriptionThenDelete() {
            final CallRecording done = recording("STOPPED");
            done.setLifecycleStatus(RecordingLifecycleStatus.COMPLETE);
            final PostCallTranscriptionJob job = new PostCallTranscriptionJob();
            job.setState("RUNNING");
            when(transcriptionJobRepository.findByRecordingId(11L))
                    .thenReturn(Optional.of(job))
                    .thenReturn(Optional.empty());
            when(recordingRepository.findByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(List.of(done));

            assertThat(service.purgeRecordingsForCall(CALL_ID)).containsEntry("status", "PENDING");

            final Map<String, Object> second = service.purgeRecordingsForCall(CALL_ID);
            assertThat(second).containsEntry("deletedDbRows", 1L).containsEntry("deletedS3Objects", 0L);
            verify(recordingRepository).deleteByCallId(CALL_ID);
        }
    }

    @Test
    @DisplayName("recording lifecycle ignores a persisted media stream id that is blank")
    void blankPersistedMediaStreamId_isIgnored() {
        final CallRecording rec = recording("STARTED");
        rec.setMediaStreamPipelineId(" ");
        when(recordingRepository.findTopByCallIdAndInitiatedByUserIdIsNullOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(rec));
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));

        assertThat(service.stopMediaStreamPipeline(CALL_ID)).containsEntry("status", "NOT_STARTED");
        verify(recordingRepository).save(rec);
        verify(kvsAttendeeStreamRegistry).clearCall(CALL_ID);
        verify(pipelinesClient, never()).deleteMediaPipeline(any(DeleteMediaPipelineRequest.class));
    }

    @Nested
    @DisplayName("failure logging paths")
    class FailurePaths {

        @Test
        @DisplayName("start without a media pipelines client marks the reservation failed")
        void startWithoutAws_unavailable() {
            ReflectionTestUtils.setField(service, "pipelinesClient", null);
            when(chimeService.getMeetingId(CALL_ID)).thenReturn(MEETING_ID);

            assertThat(service.startRecordingTyped(CALL_ID, null, false).status())
                    .isEqualTo(RecordingStartResult.Status.UNAVAILABLE);
        }

        @Test
        @DisplayName("a non-404 capture delete failure keeps the stop retryable")
        void deleteFailure_retryable() {
            final CallRecording rec = recording("STARTED");
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.deleteMediaCapturePipeline(any(DeleteMediaCapturePipelineRequest.class)))
                    .thenThrow(new RuntimeException("throttled"));

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("status", "RETRYABLE_FAILURE").containsEntry("message", "throttled");
        }

        @Test
        @DisplayName("a concatenation start failure leaves finalization retryable")
        void concatenationFailure_finalizeRetryable() {
            final CallRecording rec = recording("STARTED");
            rec.setS3Bucket(BUCKET);
            rec.setS3Prefix(S3_PREFIX);
            when(recordingRepository.findActiveByCallId(CALL_ID)).thenReturn(Optional.of(rec));
            when(pipelinesClient.createMediaConcatenationPipeline(
                            any(CreateMediaConcatenationPipelineRequest.class)))
                    .thenThrow(new RuntimeException("concat limit"));

            final Map<String, Object> result = service.stopRecording(CALL_ID);

            assertThat(result).containsEntry("recordingStatus", "FINALIZE_RETRYABLE");
            assertThat(rec.getConcatenationStatus()).isEqualTo("FAILED");
        }

        @Test
        @DisplayName("a presigner failure returns ERROR for playback")
        void presignFailure_returnsError() {
            final CallRecording rec = stoppedWithLocation();
            rec.setConcatenationStatus("READY");
            s3Objects.add(PLAYABLE_KEY);
            when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID)).thenReturn(Optional.of(rec));
            when(s3Presigner.presignGetObject(
                            any(software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest.class)))
                    .thenThrow(new RuntimeException("presign failed"));

            assertThat(service.generatePlaybackUrl(CALL_ID))
                    .containsEntry("status", "ERROR")
                    .containsEntry("message", "presign failed");
        }

        @Test
        @DisplayName("stopRecordingTyped maps the stop map to a typed result")
        void stopRecordingTyped_mapsResult() {
            final RecordingStopResult result = service.stopRecordingTyped(CALL_ID);

            assertThat(result.status()).isEqualTo(RecordingStopResult.Status.NOT_RECORDING);
            assertThat(result.callId()).isEqualTo(CALL_ID);
        }

        @Test
        @DisplayName("reconcile re-drives a finalization-retryable stop that now succeeds")
        void reconcile_retryStopSucceeds() {
            final CallRecording pending = recording("FINALIZE_RETRYABLE");
            pending.setCallId("ok-call");
            when(recordingRepository.findTop100ByStatusOrderByStartedAtDesc("FINALIZE_RETRYABLE"))
                    .thenReturn(List.of(pending));

            service.reconcileCompletedRecordingCleanup();

            verify(recordingRepository).findActiveByCallId("ok-call");
        }
    }
}
