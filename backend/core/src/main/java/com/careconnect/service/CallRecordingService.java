package com.careconnect.service;

import com.careconnect.model.CallRecording;
import com.careconnect.repository.CallRecordingRepository;
import jakarta.annotation.PostConstruct;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ArtifactsConcatenationState;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ArtifactsConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ArtifactsState;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.AudioArtifactsConcatenationState;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.AudioArtifactsConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.AudioMuxType;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ChimeSdkMeetingConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CompositedVideoArtifactsConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ConcatenationSinkType;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ConcatenationSourceType;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ContentArtifactsConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ContentShareLayoutOption;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaCapturePipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaConcatenationPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.CreateMediaConcatenationPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaCapturePipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaCapturePipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GridViewConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.LayoutOption;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineSinkType;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineSourceType;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineStatus;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.ResolutionOption;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.VideoArtifactsConfiguration;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.VideoMuxType;
import software.amazon.awssdk.services.iam.IamClient;
import software.amazon.awssdk.services.iam.model.CreateServiceLinkedRoleRequest;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.BucketAlreadyExistsException;
import software.amazon.awssdk.services.s3.model.BucketAlreadyOwnedByYouException;
import software.amazon.awssdk.services.s3.model.CommonPrefix;
import software.amazon.awssdk.services.s3.model.CreateBucketConfiguration;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.Delete;
import software.amazon.awssdk.services.s3.model.DeleteObjectsRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.ObjectIdentifier;
import software.amazon.awssdk.services.s3.model.CORSConfiguration;
import software.amazon.awssdk.services.s3.model.CORSRule;
import software.amazon.awssdk.services.s3.model.PutBucketCorsRequest;
import software.amazon.awssdk.services.s3.model.PutBucketPolicyRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityResponse;

/**
 * Manages call recording via AWS Chime SDK Media Capture Pipelines.
 *
 * <p>Each recording corresponds to one Chime SDK meeting and is written in real-time to a dedicated
 * S3 prefix under the configured bucket. Presigned URLs are generated for playback access
 * (15-minute expiry).
 *
 * <p>Fargate IAM task role requires: chime:CreateMediaCapturePipeline
 * chime:CreateMediaConcatenationPipeline chime:DeleteMediaCapturePipeline chime:GetMediaPipeline
 * chime:GetMediaCapturePipeline s3:PutObject (on recording bucket) s3:GetObject (on recording
 * bucket, for presigned URLs)
 */
@Service
public class CallRecordingService {

  private static final Logger log = LoggerFactory.getLogger(CallRecordingService.class);
  private static final DateTimeFormatter S3_TS_FORMAT =
      DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss");
  private static final int PRESIGNED_URL_TTL_MINUTES = 15;
  private static final String CONCATENATION_STATUS_NOT_REQUESTED = "NOT_REQUESTED";
  private static final String CONCATENATION_STATUS_PROCESSING = "PROCESSING";
  private static final String CONCATENATION_STATUS_READY = "READY";
  private static final String CONCATENATION_STATUS_FAILED = "FAILED";
  private static final String STATUS_STARTED = "STARTED";
  private static final String STATUS_STOPPED = "STOPPED";
  private static final int MAX_KEYS_SMALL = 20;
  private static final int MAX_KEYS_MEDIUM = 50;
  private static final int MAX_KEYS_LARGE = 1000;
  private static final int SLR_RETRY_DELAY_MS = 5000;
  private static final int PIPELINE_ID_MIN_LENGTH = 32;

  // tracks active pipeline IDs so we can stop them cleanly
  private final Map<String, String> activePipelineIds = new ConcurrentHashMap<>();

  @Autowired(required = false)
  private ChimeSdkMediaPipelinesClient pipelinesClient;

  @Autowired(required = false)
  private StsClient stsClient;

  @Autowired(required = false)
  private S3Presigner s3Presigner;

  @Autowired(required = false)
  private S3Client s3Client;

  @Autowired(required = false)
  private IamClient iamClient;

  @Autowired(required = false)
  private Region defaultAwsRegion;

  @Autowired private ChimeService chimeService;

  @Autowired private CallRecordingRepository recordingRepository;

  @Autowired private PostCallTranscriptionService postCallTranscriptionService;

  @Value("${careconnect.recording.enabled:false}")
  private boolean recordingEnabled;

  @Value("${careconnect.recording.presigned-url-ttl-minutes:15}")
  private int presignedUrlTtlMinutes;

  @Value("${careconnect.recording.raw-cleanup.enabled:true}")
  private boolean rawCleanupEnabled;

  @Value("${careconnect.cors_allowed:http://localhost:*}")
  private String corsAllowedOrigins;

  @Value("${careconnect.recording.cors-allow-wildcard:true}")
  private boolean recordingCorsAllowWildcard;

  // Cached AWS account ID (looked up once via STS on first use)
  private String cachedAccountId;

  // Cached auto-derived bucket name: careconnect-recordings-{accountId}-{region}
  private String cachedRecordingBucket;

  // ================================================================
  // STARTUP INITIALISATION
  // ================================================================

  /**
   * Eagerly provisions the two AWS prerequisites for Chime Media Capture Pipelines at application
   * startup so they are ready before any recording attempt:
   *
   * <p>1. AWSServiceRoleForAmazonChimeSDKMediaPipelines — created once per AWS account 2. Recording
   * S3 bucket + Chime bucket policy — created once per account/region
   *
   * <p>Running at startup (rather than lazily on first recording) avoids IAM propagation delays
   * that would otherwise cause the first recording attempt to fail. All operations are idempotent —
   * safe to run on every restart.
   */
  @PostConstruct
  public void initRecordingInfrastructure() {
    if (!recordingEnabled || !isAwsAvailable()) {
      return;
    }
    if (log.isInfoEnabled()) {
      log.info("Recording enabled — provisioning AWS prerequisites at startup…");
    }
    // SLR first — bucket policy setup can proceed in parallel but SLR needs time to propagate
    ensureChimeMediaPipelinesServiceLinkedRole();
    resolveOrCreateRecordingBucket();
  }

  // ================================================================
  // START RECORDING
  // ================================================================

  /**
   * Starts a Chime Media Capture Pipeline for the given callId. The Chime meeting must already be
   * active. Returns a map describing the recording that was started.
   */
  public Map<String, Object> startRecording(final String callId, final Long initiatedByUserId) {
    if (!recordingEnabled) {
      return Map.of(
          "status", "DISABLED", "message", "Recording is not enabled in this environment");
    }

    final String meetingId = chimeService.getMeetingId(callId);
    if (meetingId == null) {
      return Map.of(
          "status", "ERROR", "message", "No active Chime meeting found for callId: " + callId);
    }

    if (activePipelineIds.containsKey(callId)) {
      if (initiatedByUserId != null) {
        return Map.of(
            "status", "POLICY_BLOCKED",
            "pipelineId", activePipelineIds.get(callId),
            "message", "A transcription-only system capture is already active");
      }
      return Map.of(
          "status", "ALREADY_RECORDING",
          "pipelineId", activePipelineIds.get(callId),
          "message", "Recording already in progress for this call");
    }

    if (!isAwsAvailable()) {
      if (log.isWarnEnabled()) {
        log.warn(
            "AWS Chime Media Pipelines not available — recording skipped for callId={}", callId);
      }
      return Map.of("status", "UNAVAILABLE", "message", "AWS media pipeline client not available");
    }

    final String bucket = resolveOrCreateRecordingBucket();
    if (bucket == null) {
      return Map.of(
          "status", "ERROR", "message", "Could not resolve or create the recording bucket");
    }

    final String timestamp = LocalDateTime.now().format(S3_TS_FORMAT);
    final String s3Prefix = "recordings/" + callId + "/" + timestamp + "/";
    final String accountId = getAwsAccountId();
    if (accountId == null) {
      return Map.of(
          "status", "ERROR", "message", "Could not resolve AWS account ID for meeting ARN");
    }

    final String sourceArn = "arn:aws:chime::" + accountId + ":meeting/" + meetingId;
    final String sinkArn = "arn:aws:s3:::" + bucket;

    try {
      final CreateMediaCapturePipelineRequest request =
          CreateMediaCapturePipelineRequest.builder()
              .sourceType(MediaPipelineSourceType.CHIME_SDK_MEETING)
              .sourceArn(sourceArn)
              .sinkType(MediaPipelineSinkType.S3_BUCKET)
              .sinkArn(sinkArn)
              .clientRequestToken(UUID.randomUUID().toString())
              .chimeSdkMeetingConfiguration(
                  ChimeSdkMeetingConfiguration.builder()
                      .artifactsConfiguration(
                          ArtifactsConfiguration.builder()
                              .audio(
                                  AudioArtifactsConfiguration.builder()
                                      .muxType(AudioMuxType.AUDIO_ONLY)
                                      .build())
                              // Individual video tiles not needed — composited view captures all
                              // participants; concatenation merges this with audio into one MP4.
                              .video(
                                  VideoArtifactsConfiguration.builder()
                                      .state(ArtifactsState.DISABLED)
                                      .muxType(VideoMuxType.VIDEO_ONLY)
                                      .build())
                              .content(
                                  ContentArtifactsConfiguration.builder()
                                      .state(ArtifactsState.DISABLED)
                                      .build())
                              .compositedVideo(
                                  CompositedVideoArtifactsConfiguration.builder()
                                      .layout(LayoutOption.GRID_VIEW)
                                      .resolution(ResolutionOption.FHD)
                                      .gridViewConfiguration(
                                          GridViewConfiguration.builder()
                                              .contentShareLayout(
                                                  ContentShareLayoutOption.ACTIVE_SPEAKER_ONLY)
                                              .build())
                                      .build())
                              .build())
                      .build())
              .build();

      final CreateMediaCapturePipelineResponse response = createPipelineWithSlrRetry(request);
      final String pipelineId = response.mediaCapturePipeline().mediaPipelineId();

      activePipelineIds.put(callId, pipelineId);

      final CallRecording recording = new CallRecording();
      recording.setCallId(callId);
      recording.setPipelineId(pipelineId);
      recording.setS3Bucket(bucket);
      recording.setS3Prefix(s3Prefix);
      recording.setStatus(STATUS_STARTED);
      recording.setConcatenationStatus(CONCATENATION_STATUS_NOT_REQUESTED);
      recording.setInitiatedByUserId(initiatedByUserId);
      recording.setStartedAt(LocalDateTime.now());
      recordingRepository.save(recording);

      if (log.isInfoEnabled()) {
        log.info(
            "Recording started callId={} pipelineId={} s3Prefix={}", callId, pipelineId, s3Prefix);
      }

      final Map<String, Object> result = new HashMap<>();
      result.put("status", "STARTED");
      result.put("callId", callId);
      result.put("pipelineId", pipelineId);
      result.put("s3Bucket", bucket);
      result.put("s3Prefix", s3Prefix);
      result.put("startedAt", recording.getStartedAt().toString());
      return result;

    } catch (Exception e) {
      if (log.isErrorEnabled()) {
        log.error("Failed to start recording for callId={}: {}", callId, e.getMessage(), e);
      }

      final CallRecording failed = new CallRecording();
      failed.setCallId(callId);
      failed.setStatus("FAILED");
      failed.setInitiatedByUserId(initiatedByUserId);
      failed.setStartedAt(LocalDateTime.now());
      failed.setErrorMessage(e.getMessage());
      recordingRepository.save(failed);

      return Map.of("status", "ERROR", "message", e.getMessage());
    }
  }

  // ================================================================
  // STOP RECORDING
  // ================================================================

  /**
   * Stops the active capture pipeline for a call. Safe to call even if no recording is active
   * (no-op).
   */
  public Map<String, Object> stopRecording(final String callId) {
    String pipelineId = activePipelineIds.remove(callId);
    CallRecording recording = null;
    if (pipelineId == null) {
      // Check DB for a STARTED entry (e.g. after restart)
      final Optional<CallRecording> dbRec =
          recordingRepository.findTopByCallIdOrderByStartedAtDesc(callId);
      if (dbRec.isPresent() && STATUS_STARTED.equals(dbRec.get().getStatus())) {
        recording = dbRec.get();
        pipelineId = dbRec.get().getPipelineId();
      }
    }

    if (pipelineId == null) {
      if (log.isDebugEnabled()) {
        log.debug("No active recording pipeline found for callId={}", callId);
      }
      return Map.of("status", "NOT_RECORDING", "callId", callId);
    }

    if (recording == null) {
      recording = recordingRepository.findTopByCallIdOrderByStartedAtDesc(callId).orElse(null);
    }
    if (recording == null) {
      return Map.of("status", "NOT_RECORDING", "callId", callId);
    }

    finalizeRecordingInDb(recording);

    if (!isAwsAvailable()) {
      return Map.of("status", "STOPPED", "callId", callId, "pipelineId", pipelineId);
    }

    final String capturePipelineArn = resolveCapturePipelineArn(pipelineId);
    String warning = null;
    try {
      pipelinesClient.deleteMediaCapturePipeline(
          DeleteMediaCapturePipelineRequest.builder().mediaPipelineId(pipelineId).build());

    } catch (Exception e) {
      // Pipeline may have been auto-terminated by Chime when the meeting ended
      if (log.isWarnEnabled()) {
        log.warn(
            "Could not delete pipeline {} for callId={} (may already be gone): {}",
            pipelineId,
            callId,
            e.getMessage());
      }
      warning = e.getMessage();
    }

    final Map<String, Object> result = new HashMap<>();
    result.put("status", "STOPPED");
    result.put("callId", callId);
    result.put("pipelineId", pipelineId);

    if (capturePipelineArn != null) {
      try {
        final CreateMediaConcatenationPipelineResponse response =
            createConcatenationPipeline(recording, capturePipelineArn);
        final String concatenationPipelineId =
            response.mediaConcatenationPipeline().mediaPipelineId();
        recording.setConcatenationPipelineId(concatenationPipelineId);
        recording.setConcatenationStatus(CONCATENATION_STATUS_PROCESSING);
        recording.setErrorMessage(null);
        recordingRepository.save(recording);
        result.put("concatenationPipelineId", concatenationPipelineId);
        result.put("concatenationStatus", CONCATENATION_STATUS_PROCESSING);
        if (log.isInfoEnabled()) {
          log.info(
              "Recording concatenation started callId={} concatPipelineId={}",
              callId,
              concatenationPipelineId);
        }
      } catch (Exception e) {
        recording.setConcatenationStatus(CONCATENATION_STATUS_FAILED);
        recording.setErrorMessage(e.getMessage());
        recordingRepository.save(recording);
        result.put("concatenationStatus", CONCATENATION_STATUS_FAILED);
        result.put("concatenationWarning", e.getMessage());
        if (log.isWarnEnabled()) {
          log.warn(
              "Failed to start recording concatenation for callId={}: {}", callId, e.getMessage());
        }
      }
    } else {
      recording.setConcatenationStatus(CONCATENATION_STATUS_FAILED);
      recording.setErrorMessage("Could not resolve capture pipeline ARN for concatenation");
      recordingRepository.save(recording);
      result.put("concatenationStatus", CONCATENATION_STATUS_FAILED);
    }

    if (warning != null && !warning.isBlank()) {
      result.put("warning", warning);
    }
    return result;
  }

  // ================================================================
  // GET STATUS / METADATA
  // ================================================================

  /** Returns the latest recording metadata for a call (from DB + optional live pipeline status). */
  public Map<String, Object> getRecordingStatus(final String callId) {
    final Optional<CallRecording> opt =
        recordingRepository.findTopByCallIdOrderByStartedAtDesc(callId);
    if (opt.isEmpty()) {
      return Map.of("callId", callId, "status", "NO_RECORDING");
    }

    final CallRecording rec = opt.get();
    refreshConcatenationStatus(rec);
    final Map<String, Object> result = buildRecordingMap(rec);

    // Enrich with live pipeline status if still active and AWS available
    final String pipelineId = activePipelineIds.get(callId);
    if (pipelineId != null && isAwsAvailable()) {
      try {
        final GetMediaCapturePipelineResponse live =
            pipelinesClient.getMediaCapturePipeline(
                GetMediaCapturePipelineRequest.builder().mediaPipelineId(pipelineId).build());
        result.put("liveStatus", live.mediaCapturePipeline().statusAsString());
      } catch (Exception e) {
        if (log.isDebugEnabled()) {
          log.debug("Could not fetch live pipeline status for {}: {}", pipelineId, e.getMessage());
        }
      }
    }
    return result;
  }

  /** Returns all recordings for a given call (full history). */
  public List<Map<String, Object>> getRecordingsForCall(final String callId) {
    return recordingRepository.findByCallIdOrderByStartedAtDesc(callId).stream()
        .map(this::buildRecordingMap)
        .toList();
  }

  /** Returns all recordings initiated by a specific user. */
  public List<Map<String, Object>> getRecordingsByUser(final Long userId) {
    return recordingRepository.findByInitiatedByUserIdOrderByStartedAtDesc(userId).stream()
        .map(this::buildRecordingMap)
        .toList();
  }

  /** Returns all recordings (for admin use). */
  public List<Map<String, Object>> getAllRecordings() {
    return recordingRepository.findAll().stream().map(this::buildRecordingMap).toList();
  }

  // ================================================================
  // PRESIGNED URL FOR PLAYBACK
  // ================================================================

  /**
   * Generates a presigned S3 URL for the composited recording file. The URL expires after the
   * configured TTL (default 15 minutes).
   *
   * <p>Chime writes the composited video to: {s3Prefix}video/composited/{uuid}.mp4 We return the
   * prefix URL; callers should list the prefix if they need a specific file path once recording has
   * finished.
   */
  public Map<String, Object> generatePlaybackUrl(final String callId) {
    final Optional<CallRecording> opt =
        recordingRepository.findTopByCallIdOrderByStartedAtDesc(callId);
    if (opt.isEmpty()) {
      return Map.of("status", "NO_RECORDING", "callId", callId);
    }

    final CallRecording rec = opt.get();
    if (rec.getInitiatedByUserId() == null) {
      return Map.of(
          "status", "TRANSCRIPTION_ONLY",
          "callId", callId,
          "playbackReady", false,
          "message", "System capture is retained for transcription only");
    }
    refreshConcatenationStatus(rec);
    if (rec.getS3Bucket() == null || rec.getS3Prefix() == null) {
      return Map.of("status", "ERROR", "message", "Recording has no S3 location stored");
    }

    if (s3Presigner == null) {
      return Map.of(
          "status", "UNAVAILABLE", "message", "S3 presigner not available in this environment");
    }

    try {
      final String videoKey = resolvePlayableVideoKey(rec);
      if (videoKey == null) {
        final Map<String, Object> processing = new HashMap<>();
        processing.put("callId", callId);
        processing.put("status", "PROCESSING");
        processing.put("message", playbackPendingMessage(rec));
        processing.put("recordingStatus", rec.getStatus());
        processing.put("concatenationStatus", rec.getConcatenationStatus());
        processing.put("transcriptionStatus", rec.getTranscriptionStatus());
        processing.put("playbackReady", false);
        return processing;
      }

      final GetObjectPresignRequest presignRequest =
          GetObjectPresignRequest.builder()
              .signatureDuration(Duration.ofMinutes(presignedUrlTtlMinutes))
              .getObjectRequest(
                  GetObjectRequest.builder().bucket(rec.getS3Bucket()).key(videoKey).build())
              .build();

      final PresignedGetObjectRequest presignedRequest =
          s3Presigner.presignGetObject(presignRequest);

      final Map<String, Object> playbackResult = new HashMap<>();
      playbackResult.put("callId", callId);
      playbackResult.put("s3Bucket", rec.getS3Bucket());
      playbackResult.put("s3Prefix", rec.getS3Prefix());
      playbackResult.put("s3Key", videoKey);
      playbackResult.put("playbackUrl", presignedRequest.url().toString());
      playbackResult.put("expiresInMinutes", presignedUrlTtlMinutes);
      playbackResult.put("recordingStatus", rec.getStatus());
      playbackResult.put("concatenationStatus", rec.getConcatenationStatus());
      playbackResult.put("transcriptionStatus", rec.getTranscriptionStatus());
      // System recordings (initiatedByUserId == null) are transcription-only; never allow playback.
      // User-initiated recordings with a resolved video key are ready to play.
      playbackResult.put("playbackReady", rec.getInitiatedByUserId() != null);
      playbackResult.put(
          "recordingStartedAt",
          rec.getStartedAt() != null
              ? rec.getStartedAt().atZone(ZoneOffset.UTC).toInstant().toString()
              : null);
      return playbackResult;

    } catch (Exception e) {
      if (log.isErrorEnabled()) {
        log.error("Failed to generate presigned URL for callId={}: {}", callId, e.getMessage(), e);
      }
      return Map.of("status", "ERROR", "message", e.getMessage());
    }
  }

  // ================================================================
  // PRIVATE HELPERS
  // ================================================================

  private void finalizeRecordingInDb(final CallRecording rec) {
    if (rec == null) {
      return;
    }
    if (!STATUS_STARTED.equals(rec.getStatus())) {
      return;
    }

    final LocalDateTime endedAt = LocalDateTime.now();
    rec.setStatus(STATUS_STOPPED);
    rec.setEndedAt(endedAt);

    if (rec.getStartedAt() != null) {
      final long secs = Duration.between(rec.getStartedAt(), endedAt).getSeconds();
      rec.setDurationSeconds(secs);
    }
    recordingRepository.save(rec);
  }

  private Map<String, Object> buildRecordingMap(final CallRecording rec) {
    final Map<String, Object> m = new HashMap<>();
    m.put("id", rec.getId());
    m.put("callId", rec.getCallId());
    m.put("pipelineId", rec.getPipelineId());
    m.put("s3Bucket", rec.getS3Bucket());
    m.put("s3Prefix", rec.getS3Prefix());
    m.put("status", rec.getStatus());
    m.put("concatenationPipelineId", rec.getConcatenationPipelineId());
    m.put("concatenationStatus", rec.getConcatenationStatus());
    m.put("transcriptionStatus", rec.getTranscriptionStatus());
    // System recordings (initiatedByUserId == null) are transcription-only; never allow playback
    m.put("playbackReady",
        rec.getInitiatedByUserId() != null && resolvePlayableVideoKey(rec) != null);
    m.put("initiatedByUserId", rec.getInitiatedByUserId());
    m.put("startedAt", rec.getStartedAt() != null ? rec.getStartedAt().toString() : null);
    m.put("endedAt", rec.getEndedAt() != null ? rec.getEndedAt().toString() : null);
    m.put("durationSeconds", rec.getDurationSeconds());
    m.put("errorMessage", rec.getErrorMessage());
    return m;
  }

  private CreateMediaConcatenationPipelineResponse createConcatenationPipeline(
      final CallRecording recording, final String capturePipelineArn) {
    final String destinationArn = buildConcatenationDestinationArn(recording);
    return pipelinesClient.createMediaConcatenationPipeline(
        CreateMediaConcatenationPipelineRequest.builder()
            .sources(
                source ->
                    source
                        .type(ConcatenationSourceType.MEDIA_CAPTURE_PIPELINE)
                        .mediaCapturePipelineSourceConfiguration(
                            sourceConfig ->
                                sourceConfig
                                    .mediaPipelineArn(capturePipelineArn)
                                    .chimeSdkMeetingConfiguration(
                                        config ->
                                            config.artifactsConfiguration(
                                                artifacts ->
                                                    artifacts
                                                        .audio(
                                                            audio ->
                                                                audio.state(
                                                                    AudioArtifactsConcatenationState
                                                                        .ENABLED))
                                                        // Individual tiles disabled in capture;
                                                        // only compositedVideo is written to S3.
                                                        .video(
                                                            video ->
                                                                video.state(
                                                                    ArtifactsConcatenationState
                                                                        .DISABLED))
                                                        .content(
                                                            content ->
                                                                content.state(
                                                                    ArtifactsConcatenationState
                                                                        .DISABLED))
                                                        .dataChannel(
                                                            dataChannel ->
                                                                dataChannel.state(
                                                                    ArtifactsConcatenationState
                                                                        .DISABLED))
                                                        .meetingEvents(
                                                            meetingEvents ->
                                                                meetingEvents.state(
                                                                    ArtifactsConcatenationState
                                                                        .DISABLED))
                                                        .transcriptionMessages(
                                                            messages ->
                                                                messages.state(
                                                                    ArtifactsConcatenationState
                                                                        .DISABLED))
                                                        .compositedVideo(
                                                            video ->
                                                                video.state(
                                                                    ArtifactsConcatenationState
                                                                        .ENABLED))))))
            .sinks(
                sink ->
                    sink.type(ConcatenationSinkType.S3_BUCKET)
                        .s3BucketSinkConfiguration(bucket -> bucket.destination(destinationArn)))
            .clientRequestToken(UUID.randomUUID().toString())
            .build());
  }

  private String resolveCapturePipelineArn(final String pipelineId) {
    if (!isAwsAvailable() || pipelineId == null || pipelineId.isBlank()) {
      return null;
    }
    try {
      final GetMediaCapturePipelineResponse response =
          pipelinesClient.getMediaCapturePipeline(
              GetMediaCapturePipelineRequest.builder().mediaPipelineId(pipelineId).build());
      return response.mediaCapturePipeline().mediaPipelineArn();
    } catch (Exception e) {
      if (log.isWarnEnabled()) {
        log.warn("Could not resolve capture pipeline ARN for {}: {}", pipelineId, e.getMessage());
      }
      return null;
    }
  }

  private void refreshConcatenationStatus(final CallRecording rec) {
    if (rec == null || rec.getS3Bucket() == null || rec.getS3Prefix() == null) {
      return;
    }

    String playableKey = resolvePlayableVideoKeyWithoutRefresh(rec);
    String existingStatus = rec.getConcatenationStatus();
    String nextStatus = existingStatus;
    String nextErrorMessage = rec.getErrorMessage();

    if (playableKey != null) {
      nextStatus = CONCATENATION_STATUS_READY;
      if (nextErrorMessage != null
          && nextErrorMessage.startsWith(
              "Concatenation pipeline completed but no stitched video was found")) {
        nextErrorMessage = null;
      }
      cleanupRawArtifactsAfterConcatenation(rec, playableKey);
      // Trigger post-call transcription for all recordings.
      // For system recordings (initiatedByUserId == null) the service also deletes the
      // concatenated file after transcription; user recordings are kept for playback.
      if (!CONCATENATION_STATUS_READY.equals(existingStatus)) {
        postCallTranscriptionService.transcribeAndCleanup(rec.getCallId(), rec, playableKey);
      }
    } else if (rec.getConcatenationPipelineId() != null
        && !rec.getConcatenationPipelineId().isBlank()) {
      nextStatus =
          resolveConcatenationPipelineStatus(rec.getConcatenationPipelineId(), existingStatus);
      if (CONCATENATION_STATUS_FAILED.equals(nextStatus)) {
        nextErrorMessage = buildMissingConcatenatedOutputMessage(rec);
      }
    } else if ("STOPPED".equals(rec.getStatus())) {
      nextStatus = CONCATENATION_STATUS_NOT_REQUESTED;
    }

    final boolean statusChanged = nextStatus != null && !nextStatus.equals(existingStatus);
    final boolean errorChanged = !java.util.Objects.equals(nextErrorMessage, rec.getErrorMessage());
    if (statusChanged || errorChanged) {
      rec.setConcatenationStatus(nextStatus);
      rec.setErrorMessage(nextErrorMessage);
      recordingRepository.save(rec);
    }
  }

  /** Deletes raw recording artifacts for a call when the stitched video is ready. */
  public Map<String, Object> cleanupRawArtifactsForCall(final String callId) {
    final Optional<CallRecording> opt =
        recordingRepository.findTopByCallIdOrderByStartedAtDesc(callId);
    if (opt.isEmpty()) {
      return Map.of("callId", callId, "status", "NO_RECORDING", "deletedObjects", 0L);
    }

    final CallRecording rec = opt.get();
    String playableKey = resolvePlayableVideoKeyWithoutRefresh(rec);
    if (playableKey == null || playableKey.isBlank()) {
      refreshConcatenationStatus(rec);
      playableKey = resolvePlayableVideoKeyWithoutRefresh(rec);
    }
    if (playableKey == null || playableKey.isBlank()) {
      return Map.of(
          "callId",
          callId,
          "status",
          "PLAYBACK_NOT_READY",
          "deletedObjects",
          0L,
          "message",
          "Final stitched video was not found; raw artifacts were not deleted.");
    }

    final long deletedObjects = cleanupRawArtifactsAfterConcatenation(rec, playableKey);
    return Map.of(
        "callId", callId,
        "status", "CLEANED",
        "deletedObjects", deletedObjects,
        "playableKey", playableKey);
  }

  /** Periodically reconciles stopped recordings and attempts raw artifact cleanup. */
  @Scheduled(fixedDelayString = "${careconnect.recording.raw-cleanup.interval-ms:60000}")
  public void reconcileCompletedRecordingCleanup() {
    if (!recordingEnabled || !rawCleanupEnabled || s3Client == null) {
      return;
    }

    final List<CallRecording> recentStoppedRecordings =
        recordingRepository.findTop100ByStatusOrderByStartedAtDesc("STOPPED");
    for (final CallRecording recording : recentStoppedRecordings) {
      if (recording == null) {
        continue;
      }
      try {
        refreshConcatenationStatus(recording);
      } catch (Exception e) {
        if (log.isDebugEnabled()) {
          log.debug(
              "Raw cleanup reconciliation skipped for callId {}: {}",
              recording.getCallId(),
              e.getMessage());
        }
      }
    }
  }

  private String resolveConcatenationPipelineStatus(
      final String pipelineId, final String fallbackStatus) {
    if (!isAwsAvailable()) {
      return fallbackStatus == null ? CONCATENATION_STATUS_PROCESSING : fallbackStatus;
    }
    try {
      final GetMediaPipelineResponse response =
          pipelinesClient.getMediaPipeline(
              GetMediaPipelineRequest.builder().mediaPipelineId(pipelineId).build());
      if (response.mediaPipeline() == null
          || response.mediaPipeline().mediaConcatenationPipeline() == null) {
        return fallbackStatus == null ? CONCATENATION_STATUS_PROCESSING : fallbackStatus;
      }
      final MediaPipelineStatus status =
          response.mediaPipeline().mediaConcatenationPipeline().status();
      if (status == MediaPipelineStatus.FAILED) {
        return CONCATENATION_STATUS_FAILED;
      }
      if (status == MediaPipelineStatus.STOPPED) {
        // STOPPED means the concatenation pipeline finished successfully.
        // Return PROCESSING so the next refresh finds the output file in S3.
        return CONCATENATION_STATUS_PROCESSING;
      }
      return CONCATENATION_STATUS_PROCESSING;
    } catch (Exception e) {
      if (log.isDebugEnabled()) {
        log.debug(
            "Could not fetch concatenation pipeline status for {}: {}", pipelineId, e.getMessage());
      }
      return fallbackStatus == null ? CONCATENATION_STATUS_PROCESSING : fallbackStatus;
    }
  }

  private String resolvePlayableVideoKey(final CallRecording rec) {
    refreshConcatenationStatus(rec);
    return resolvePlayableVideoKeyWithoutRefresh(rec);
  }

  private String resolvePlayableVideoKeyWithoutRefresh(final CallRecording rec) {
    if (rec == null || s3Client == null || rec.getS3Bucket() == null || rec.getS3Prefix() == null) {
      return null;
    }

    String concatenatedKey = resolveConcatenatedVideoKey(rec);
    if (concatenatedKey != null) {
      return concatenatedKey;
    }

    // Preserve playback for older recordings created before concatenation support.
    if (rec.getConcatenationPipelineId() == null || rec.getConcatenationPipelineId().isBlank()) {
      return resolveLegacyChunkKey(rec);
    }
    return null;
  }

  private String resolveConcatenatedVideoKey(final CallRecording rec) {
    final String concatenatedPrefix = buildConcatenatedPrefix(rec);
    final List<String> candidatePrefixes =
        List.of(concatenatedPrefix + "composited-video/", concatenatedPrefix + "video/");

    if (rec.getConcatenationPipelineId() != null && !rec.getConcatenationPipelineId().isBlank()) {
      for (final String prefix : candidatePrefixes) {
        final String exactKey = prefix + rec.getConcatenationPipelineId() + ".mp4";
        final ListObjectsV2Response exact =
            s3Client.listObjectsV2(
                ListObjectsV2Request.builder()
                    .bucket(rec.getS3Bucket())
                    .prefix(exactKey)
                    .maxKeys(1)
                    .build());
        final boolean exists =
            exact.contents().stream().anyMatch(obj -> exactKey.equals(obj.key()));
        if (exists) {
          return exactKey;
        }
      }
    }

    for (final String prefix : candidatePrefixes) {
      final ListObjectsV2Response listing =
          s3Client.listObjectsV2(
              ListObjectsV2Request.builder()
                  .bucket(rec.getS3Bucket())
                  .prefix(prefix)
                  .maxKeys(20)
                  .build());
      final String found =
          listing.contents().stream()
              .filter(o -> o.key().endsWith(".mp4"))
              .findFirst()
              .map(software.amazon.awssdk.services.s3.model.S3Object::key)
              .orElse(null);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  private String resolveLegacyChunkKey(final CallRecording rec) {
    final String videoPrefix = rec.getS3Prefix() + "video/";
    ListObjectsV2Response listing =
        s3Client.listObjectsV2(
            ListObjectsV2Request.builder()
                .bucket(rec.getS3Bucket())
                .prefix(videoPrefix)
                .maxKeys(20)
                .build());
    return listing.contents().stream()
        .filter(o -> o.key().endsWith(".mp4"))
        .findFirst()
        .map(software.amazon.awssdk.services.s3.model.S3Object::key)
        .orElse(null);
  }

  private String buildConcatenatedPrefix(final CallRecording recording) {
    return recording.getS3Prefix() + "concatenated/";
  }

  private String buildConcatenationDestinationArn(final CallRecording recording) {
    String prefix = buildConcatenatedPrefix(recording);
    if (prefix.endsWith("/")) {
      prefix = prefix.substring(0, prefix.length() - 1);
    }
    return "arn:aws:s3:::" + recording.getS3Bucket() + "/" + prefix;
  }

  private String playbackPendingMessage(final CallRecording rec) {
    if (CONCATENATION_STATUS_FAILED.equals(rec.getConcatenationStatus())) {
      return "Recording stitching did not complete. Check the recording status or retry later.";
    }
    return "Video is still being stitched. Pull to refresh in about 1-2 minutes.";
  }

  private String buildMissingConcatenatedOutputMessage(final CallRecording rec) {
    final String pipelineId =
        rec.getConcatenationPipelineId() == null ? "unknown" : rec.getConcatenationPipelineId();
    final String expectedPrefix = buildConcatenatedPrefix(rec) + "composited-video/";
    return "Concatenation pipeline completed but no stitched video was found under "
        + rec.getS3Bucket()
        + "/"
        + expectedPrefix
        + " for pipeline "
        + pipelineId
        + ".";
  }

  private long cleanupRawArtifactsAfterConcatenation(
      final CallRecording rec, final String playableKey) {
    if (rec == null || s3Client == null || rec.getS3Bucket() == null || rec.getS3Prefix() == null) {
      return 0L;
    }
    if (playableKey == null || playableKey.isBlank()) {
      return 0L;
    }

    long deletedObjects = 0L;
    final List<String> rawPrefixes = discoverRawArtifactPrefixes(rec, playableKey);
    if (log.isInfoEnabled()) {
      log.info(
          "Attempting raw recording artifact cleanup for callId={} pipelineId={} s3Prefix={}"
              + " bucket={} playableKey={}",
          rec.getCallId(),
          rec.getPipelineId(),
          rec.getS3Prefix(),
          rec.getS3Bucket(),
          playableKey);
    }

    for (String rawPrefix : rawPrefixes) {
      if (isRecordingManagedPrefix(rec, rawPrefix)) {
        deletedObjects += deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix + "audio/");
        deletedObjects += deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix + "video/");
        deletedObjects += deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix + "content/");
        deletedObjects += deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix + "data-channel/");
        deletedObjects +=
            deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix + "meeting-events/");
        deletedObjects +=
            deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix + "transcription-messages/");
      } else {
        if (prefixContainsPlayableKey(rawPrefix, playableKey)) {
          if (log.isWarnEnabled()) {
            log.warn(
                "Skipping raw cleanup for prefix {} because it contains the playable video key {}",
                rawPrefix,
                playableKey);
          }
          continue;
        }
        deletedObjects += deleteObjectsUnderPrefix(rec.getS3Bucket(), rawPrefix);
        deletedObjects += deleteExactObjectIfPresent(rec.getS3Bucket(), rawPrefix);
        deletedObjects +=
            deleteExactObjectIfPresent(rec.getS3Bucket(), stripTrailingSlash(rawPrefix));
      }
    }

    if (deletedObjects > 0) {
      if (log.isInfoEnabled()) {
        log.info(
            "Deleted {} raw recording artifact(s) after concatenation for callId={} (kept final"
                + " video key={})",
            deletedObjects,
            rec.getCallId(),
            playableKey);
      }
    } else {
      if (log.isInfoEnabled()) {
        log.info(
            "No raw recording artifacts were deleted for callId={} during cleanup attempt",
            rec.getCallId());
      }
    }
    cleanupEmptyTopLevelPipelineMarkers(rec.getS3Bucket());
    return deletedObjects;
  }

  private List<String> discoverRawArtifactPrefixes(
      final CallRecording rec, final String playableKey) {
    final java.util.LinkedHashSet<String> prefixes = new java.util.LinkedHashSet<>();

    final String recordingPrefix = rec.getS3Prefix();
    if (recordingPrefix != null && !recordingPrefix.isBlank()) {
      prefixes.add(recordingPrefix);
    }

    final String pipelineId = rec.getPipelineId();
    if (pipelineId != null && !pipelineId.isBlank()) {
      prefixes.add(pipelineId.endsWith("/") ? pipelineId : pipelineId + "/");
    }

    final String finalFileName = playableKey.substring(playableKey.lastIndexOf('/') + 1);
    if (finalFileName.isBlank()) {
      return new java.util.ArrayList<>(prefixes);
    }

    try {
      final ListObjectsV2Response rootListing =
          s3Client.listObjectsV2(
              ListObjectsV2Request.builder()
                  .bucket(rec.getS3Bucket())
                  .delimiter("/")
                  .maxKeys(1000)
                  .build());

      for (final CommonPrefix commonPrefix : rootListing.commonPrefixes()) {
        final String prefix = commonPrefix.prefix();
        if (!isTopLevelPipelinePrefix(prefix)) {
          continue;
        }

        final ListObjectsV2Response videoListing =
            s3Client.listObjectsV2(
                ListObjectsV2Request.builder()
                    .bucket(rec.getS3Bucket())
                    .prefix(prefix + "video/")
                    .maxKeys(50)
                    .build());

        final boolean matchesFinalVideo =
            videoListing.contents().stream()
                .map(obj -> obj.key())
                .filter(key -> key != null)
                .anyMatch(key -> key.endsWith(finalFileName) || key.endsWith("-" + finalFileName));

        if (matchesFinalVideo) {
          prefixes.add(prefix);
        }
      }
    } catch (Exception e) {
      if (log.isDebugEnabled()) {
        log.debug(
            "Could not discover raw capture prefix for callId {}: {}",
            rec.getCallId(),
            e.getMessage());
      }
    }

    return new java.util.ArrayList<>(prefixes);
  }

  private boolean isRecordingManagedPrefix(final CallRecording rec, final String prefix) {
    if (rec == null || rec.getS3Prefix() == null || prefix == null) {
      return false;
    }
    return rec.getS3Prefix().equals(prefix);
  }

  private boolean prefixContainsPlayableKey(final String prefix, final String playableKey) {
    if (prefix == null || prefix.isBlank() || playableKey == null || playableKey.isBlank()) {
      return false;
    }
    return playableKey.startsWith(prefix);
  }

  private long deleteExactObjectIfPresent(final String bucket, final String key) {
    if (bucket == null || bucket.isBlank() || key == null || key.isBlank() || s3Client == null) {
      return 0L;
    }
    try {
      final ListObjectsV2Response listing =
          s3Client.listObjectsV2(
              ListObjectsV2Request.builder().bucket(bucket).prefix(key).maxKeys(1).build());
      final boolean exactExists =
          listing.contents().stream().anyMatch(obj -> key.equals(obj.key()));
      if (!exactExists) {
        return 0L;
      }
      s3Client.deleteObjects(
          DeleteObjectsRequest.builder()
              .bucket(bucket)
              .delete(Delete.builder().objects(ObjectIdentifier.builder().key(key).build()).build())
              .build());
      return 1L;
    } catch (Exception e) {
      if (log.isDebugEnabled()) {
        log.debug(
            "Could not delete exact S3 object {} from bucket {}: {}", key, bucket, e.getMessage());
      }
      return 0L;
    }
  }

  private void cleanupEmptyTopLevelPipelineMarkers(final String bucket) {
    if (bucket == null || bucket.isBlank() || s3Client == null) {
      return;
    }
    try {
      final ListObjectsV2Response rootListing =
          s3Client.listObjectsV2(
              ListObjectsV2Request.builder().bucket(bucket).delimiter("/").maxKeys(1000).build());

      for (final CommonPrefix commonPrefix : rootListing.commonPrefixes()) {
        final String prefix = commonPrefix.prefix();
        if (!isTopLevelPipelinePrefix(prefix)) {
          continue;
        }

        final ListObjectsV2Response nestedListing =
            s3Client.listObjectsV2(
                ListObjectsV2Request.builder().bucket(bucket).prefix(prefix).maxKeys(2).build());

        final boolean hasNestedObjects =
            nestedListing.contents().stream()
                .map(obj -> obj.key())
                .filter(key -> key != null)
                .anyMatch(key -> !key.equals(prefix) && !key.equals(stripTrailingSlash(prefix)));

        if (!hasNestedObjects) {
          deleteExactObjectIfPresent(bucket, prefix);
          deleteExactObjectIfPresent(bucket, stripTrailingSlash(prefix));
        }
      }
    } catch (Exception e) {
      if (log.isDebugEnabled()) {
        log.debug(
            "Could not clean empty top-level pipeline markers in bucket {}: {}",
            bucket,
            e.getMessage());
      }
    }
  }

  private boolean isTopLevelPipelinePrefix(final String prefix) {
    if (prefix == null || prefix.isBlank()) {
      return false;
    }
    final String normalized = stripTrailingSlash(prefix);
    if (normalized.isBlank() || normalized.contains("/")) {
      return false;
    }
    if ("recordings".equalsIgnoreCase(normalized)) {
      return false;
    }
    return normalized.matches("[0-9a-fA-F\\-]{32,}");
  }

  private String stripTrailingSlash(final String value) {
    if (value == null) {
      return "";
    }
    String normalized = value.trim();
    while (normalized.endsWith("/")) {
      normalized = normalized.substring(0, normalized.length() - 1);
    }
    return normalized;
  }

  private long deleteObjectsUnderPrefix(final String bucket, final String prefix) {
    if (bucket == null
        || bucket.isBlank()
        || prefix == null
        || prefix.isBlank()
        || s3Client == null) {
      return 0L;
    }

    long deletedObjects = 0L;
    String continuationToken = null;
    do {
      final ListObjectsV2Request.Builder listReq =
          ListObjectsV2Request.builder().bucket(bucket).prefix(prefix).maxKeys(1000);
      if (continuationToken != null) {
        listReq.continuationToken(continuationToken);
      }
      final ListObjectsV2Response page = s3Client.listObjectsV2(listReq.build());
      if (!page.contents().isEmpty()) {
        final List<ObjectIdentifier> keys =
            page.contents().stream()
                .map(obj -> ObjectIdentifier.builder().key(obj.key()).build())
                .toList();
        s3Client.deleteObjects(
            DeleteObjectsRequest.builder()
                .bucket(bucket)
                .delete(Delete.builder().objects(keys).build())
                .build());
        deletedObjects += keys.size();
      }
      continuationToken = page.isTruncated() ? page.nextContinuationToken() : null;
    } while (continuationToken != null);

    return deletedObjects;
  }

  /**
   * DEV/LOCAL ONLY — deletes every recording from both S3 and the database.
   *
   * <p>Iterates through all objects under the "recordings/" prefix in the auto-named bucket using
   * paginated ListObjectsV2, then issues batched DeleteObjects requests (up to 1 000 keys per call,
   * the S3 maximum). Finally truncates the call_recordings table.
   *
   * <p>Returns a summary map: { deletedS3Objects, deletedDbRows, bucket }.
   */
  public Map<String, Object> purgeAllRecordings() {
    final long deletedDbRows = recordingRepository.count();
    recordingRepository.deleteAll();
    activePipelineIds.clear();

    long deletedS3Objects = 0;
    final String bucket = resolveOrCreateRecordingBucket();

    if (bucket != null && s3Client != null) {
      try {
        String continuationToken = null;
        do {
          final ListObjectsV2Request.Builder listReq =
              ListObjectsV2Request.builder().bucket(bucket).prefix("recordings/").maxKeys(1000);
          if (continuationToken != null) {
            listReq.continuationToken(continuationToken);
          }
          final ListObjectsV2Response page = s3Client.listObjectsV2(listReq.build());

          if (!page.contents().isEmpty()) {
            final List<ObjectIdentifier> keys =
                page.contents().stream()
                    .map(obj -> ObjectIdentifier.builder().key(obj.key()).build())
                    .toList();
            s3Client.deleteObjects(
                DeleteObjectsRequest.builder()
                    .bucket(bucket)
                    .delete(Delete.builder().objects(keys).build())
                    .build());
            deletedS3Objects += keys.size();
          }

          continuationToken = page.isTruncated() ? page.nextContinuationToken() : null;
        } while (continuationToken != null);

      } catch (Exception e) {
        if (log.isWarnEnabled()) {
          log.warn("S3 purge partially failed for bucket {}: {}", bucket, e.getMessage());
        }
      }
    }

    if (log.isWarnEnabled()) {
      log.warn(
          "DEV purge: deleted {} S3 objects and {} DB rows from bucket {}",
          deletedS3Objects,
          deletedDbRows,
          bucket);
    }

    return Map.of(
        "deletedS3Objects", deletedS3Objects,
        "deletedDbRows", deletedDbRows,
        "bucket", bucket != null ? bucket : "unknown");
  }

  /** Deletes all recording metadata and S3 artifacts associated with a call. */
  @Transactional
  public Map<String, Object> purgeRecordingsForCall(final String callId) {
    final String normalizedCallId = normalizeCallId(callId);
    if (normalizedCallId == null) {
      return Map.of(
          "callId", "",
          "deletedS3Objects", 0L,
          "deletedDbRows", 0L);
    }

    activePipelineIds.remove(normalizedCallId);
    final List<CallRecording> recordings =
        recordingRepository.findByCallIdOrderByStartedAtDesc(normalizedCallId);
    final long deletedDbRows = recordings.size();
    long deletedS3Objects = 0L;

    if (s3Client != null) {
      for (final CallRecording recording : recordings) {
        deletedS3Objects +=
            deleteObjectsUnderPrefix(recording.getS3Bucket(), recording.getS3Prefix());
      }
    }

    if (deletedDbRows > 0) {
      recordingRepository.deleteByCallId(normalizedCallId);
    }

    return Map.of(
        "callId", normalizedCallId,
        "deletedS3Objects", deletedS3Objects,
        "deletedDbRows", deletedDbRows);
  }

  /**
   * Derives the recording bucket name as: careconnect-recordings-{accountId}-{region}
   *
   * <p>This makes it unique per AWS account and region with zero configuration. The bucket is
   * created automatically on first use if it does not yet exist. Result is cached so STS and S3 are
   * only contacted once per service lifetime.
   */
  private synchronized String resolveOrCreateRecordingBucket() {
    if (cachedRecordingBucket != null) {
      return cachedRecordingBucket;
    }

    final String accountId = getAwsAccountId();
    if (accountId == null) {
      return null;
    }

    final String regionId = (defaultAwsRegion != null) ? defaultAwsRegion.id() : "us-east-1";

    final String bucketName = "careconnect-recordings-" + accountId + "-" + regionId;

    if (s3Client != null) {
      try {
        // us-east-1 does not accept a LocationConstraint
        CreateBucketRequest.Builder reqBuilder = CreateBucketRequest.builder().bucket(bucketName);
        if (!"us-east-1".equals(regionId)) {
          reqBuilder.createBucketConfiguration(
              CreateBucketConfiguration.builder().locationConstraint(regionId).build());
        }
        s3Client.createBucket(reqBuilder.build());
        if (log.isInfoEnabled()) {
          log.info("Created recording bucket: {}", bucketName);
        }
      } catch (BucketAlreadyOwnedByYouException | BucketAlreadyExistsException ignored) {
        if (log.isDebugEnabled()) {
          log.debug("Recording bucket already exists: {}", bucketName);
        }
      } catch (Exception e) {
        if (log.isWarnEnabled()) {
          log.warn("Could not create recording bucket {}: {}", bucketName, e.getMessage());
        }
        // Continue — bucket may already exist but createBucket threw a different error
      }

      // AWS Chime Media Capture Pipelines require a bucket policy granting
      // chime.amazonaws.com s3:PutObject + s3:GetBucketAcl before they will
      // accept the bucket as a sink. Apply it unconditionally — it is idempotent.
      applyChimeBucketPolicy(bucketName);
      applyRecordingBucketCors(bucketName);

      // AWS also requires a service-linked role for the Chime Media Pipelines
      // service to access Chime meetings. Create it if it does not yet exist.
      ensureChimeMediaPipelinesServiceLinkedRole();
    }

    cachedRecordingBucket = bucketName;
    return bucketName;
  }

  /**
   * Applies the bucket policy required by AWS Chime Media Capture Pipelines.
   *
   * <p>Without this policy Chime rejects the bucket with: "The bucket policy does not exist" (HTTP
   * 400 BadRequest)
   *
   * <p>The policy grants mediapipelines.chime.amazonaws.com: s3:PutObject, s3:PutObjectAcl — to
   * write captured media s3:GetBucketAcl, s3:GetObject — to verify and read source media
   * s3:ListBucket — to enumerate capture artifacts for concatenation
   */
  private void applyChimeBucketPolicy(final String bucketName) {
    final String accountId = getAwsAccountId();
    if (bucketName == null || bucketName.isBlank() || accountId == null || accountId.isBlank()) {
      if (log.isWarnEnabled()) {
        log.warn("Skipping Chime bucket policy application; bucketName or accountId missing");
      }
      return;
    }

    String policy =
        """
        {
          "Version": "2012-10-17",
          "Id": "AWSChimeMediaPipelinesBucketPolicy",
          "Statement": [
            {
              "Sid": "AWSChimeMediaPipelinesObjectPolicy",
              "Effect": "Allow",
              "Principal": { "Service": "mediapipelines.chime.amazonaws.com" },
              "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetObject"
              ],
              "Resource": "arn:aws:s3:::$BUCKET_NAME$/*",
              "Condition": {
                "StringEquals": {
                  "aws:SourceAccount": "$ACCOUNT_ID$"
                },
                "ArnLike": {
                  "aws:SourceArn": "arn:aws:chime:*:$ACCOUNT_ID$:*"
                }
              }
            },
            {
              "Sid": "AWSChimeMediaPipelinesBucketPolicy",
              "Effect": "Allow",
              "Principal": { "Service": "mediapipelines.chime.amazonaws.com" },
              "Action": [
                "s3:GetBucketAcl",
                "s3:ListBucket"
              ],
              "Resource": "arn:aws:s3:::$BUCKET_NAME$",
              "Condition": {
                "StringEquals": {
                  "aws:SourceAccount": "$ACCOUNT_ID$"
                },
                "ArnLike": {
                  "aws:SourceArn": "arn:aws:chime:*:$ACCOUNT_ID$:*"
                }
              }
            }
          ]
        }"""
            .replace("$BUCKET_NAME$", bucketName)
            .replace("$ACCOUNT_ID$", accountId);
    try {
      s3Client.putBucketPolicy(
          PutBucketPolicyRequest.builder().bucket(bucketName).policy(policy).build());
      log.info("Applied Chime media capture bucket policy to: {}", bucketName);
    } catch (Exception e) {
      if (log.isErrorEnabled()) {
        log.error("Failed to apply Chime bucket policy to {}: {}", bucketName, e.getMessage());
      }
    }
  }

  /**
   * Applies S3 CORS rules required for browser inline MP4 seek (HTTP Range on presigned URLs).
   *
   * <p>Without {@code ExposeHeaders} for {@code Accept-Ranges} / {@code Content-Range}, Flutter web
   * {@code video_player} cannot seek on composited recordings (WBS §3.3.2 / M7).
   */
  private void applyRecordingBucketCors(final String bucketName) {
    if (s3Client == null || bucketName == null || bucketName.isBlank()) {
      return;
    }

    final List<String> origins = resolveS3CorsOrigins();
    try {
      s3Client.putBucketCors(
          PutBucketCorsRequest.builder()
              .bucket(bucketName)
              .corsConfiguration(
                  CORSConfiguration.builder()
                      .corsRules(
                          CORSRule.builder()
                              .allowedOrigins(origins)
                              .allowedMethods("GET", "HEAD")
                              .allowedHeaders(List.of("*"))
                              .exposeHeaders(
                                  "Accept-Ranges", "Content-Range", "Content-Length", "ETag")
                              .maxAgeSeconds(3600)
                              .build())
                      .build())
              .build());
      if (log.isInfoEnabled()) {
        log.info(
            "Applied recording bucket CORS for inline playback on {} (origins={})",
            bucketName,
            origins);
      }
    } catch (Exception e) {
      if (log.isWarnEnabled()) {
        log.warn(
            "Failed to apply recording bucket CORS to {}: {} — add s3:PutBucketCors to IAM or run"
                + " scripts/recording-bucket-cors.json once via aws s3api put-bucket-cors",
            bucketName,
            e.getMessage());
      }
    }
  }

  /**
   * Maps Spring CORS origin patterns to S3 CORS allowed origins.
   *
   * <p>S3 does not support port wildcards ({@code http://localhost:*}); when patterns are present,
   * use {@code *} so dev Flutter web ports can load presigned MP4s. Presigned URLs remain
   * time-limited and unguessable.
   */
  private List<String> resolveS3CorsOrigins() {
    final List<String> explicit = new ArrayList<>();
    if (corsAllowedOrigins == null || corsAllowedOrigins.isBlank()) {
      explicit.add("*");
      return explicit;
    }

    boolean needsWildcard = false;
    for (final String raw : corsAllowedOrigins.split(",")) {
      final String origin = raw.trim();
      if (origin.isEmpty()) {
        continue;
      }
      if ("*".equals(origin) || origin.contains("*")) {
        needsWildcard = true;
      } else {
        explicit.add(origin);
      }
    }

    if (needsWildcard || explicit.isEmpty()) {
      if (recordingCorsAllowWildcard) {
        explicit.clear();
        explicit.add("*");
      } else if (explicit.isEmpty() && log.isWarnEnabled()) {
        log.warn(
            "Recording bucket CORS requires wildcard origins for localhost dev ports but"
                + " careconnect.recording.cors-allow-wildcard=false — configure explicit"
                + " origins in careconnect.cors_allowed");
      }
    }
    return explicit;
  }

  /**
   * Creates the service-linked role required by AWS Chime SDK Media Pipelines:
   * AWSServiceRoleForAmazonChimeSDKMediaPipelines
   *
   * <p>Without this role Chime rejects pipeline creation with: "Create a service-linked role to
   * allow Amazon Chime SDK media pipelines to access Amazon Chime SDK meetings on your behalf"
   *
   * <p>This is a one-time account-level setup. If the role already exists the call throws
   * InvalidInputException which is silently ignored. Requires iam:CreateServiceLinkedRole on the
   * IAM user/task role. If that permission is missing, log a clear manual instruction.
   */
  private void ensureChimeMediaPipelinesServiceLinkedRole() {
    if (iamClient == null) {
      log.warn(
          "IAM client not available — cannot auto-create Chime Media Pipelines service-linked role."
              + " Run manually: aws iam create-service-linked-role --aws-service-name"
              + " mediapipelines.chime.amazonaws.com");
      return;
    }
    try {
      iamClient.createServiceLinkedRole(
          CreateServiceLinkedRoleRequest.builder()
              .awsServiceName("mediapipelines.chime.amazonaws.com")
              .description("Allows Chime SDK Media Pipelines to access Chime SDK meetings")
              .build());
      log.info("Created Chime Media Pipelines service-linked role");
    } catch (Exception e) {
      // InvalidInputException = role already exists — that is fine
      if (e.getMessage() != null && e.getMessage().contains("has been taken")) {
        log.debug("Chime Media Pipelines service-linked role already exists");
      } else if (e.getMessage() != null && e.getMessage().contains("not authorized")) {
        log.error(
            "Cannot auto-create Chime Media Pipelines service-linked role — missing "
                + "iam:CreateServiceLinkedRole permission. Run once manually: "
                + "aws iam create-service-linked-role "
                + "--aws-service-name mediapipelines.chime.amazonaws.com");
      } else {
        if (log.isWarnEnabled()) {
          log.warn("Unexpected result creating Chime Media Pipelines SLR: {}", e.getMessage());
        }
      }
    }
  }

  /**
   * Calls createMediaCapturePipeline with a single automatic retry if the service-linked role was
   * only just created and IAM hasn't propagated it yet. Waits 5 seconds before retrying — enough
   * for global IAM propagation in practice.
   */
  private CreateMediaCapturePipelineResponse createPipelineWithSlrRetry(
      CreateMediaCapturePipelineRequest request) {
    try {
      return pipelinesClient.createMediaCapturePipeline(request);
    } catch (Exception e) {
      if (e.getMessage() != null && e.getMessage().contains("service-linked role")) {
        log.warn(
            "Chime pipeline creation failed due to SLR propagation delay — "
                + "waiting 5s and retrying once…");
        try {
          Thread.sleep(5000);
        } catch (InterruptedException ie) {
          Thread.currentThread().interrupt();
        }
        ensureChimeMediaPipelinesServiceLinkedRole();
        return pipelinesClient.createMediaCapturePipeline(request);
      }
      throw e;
    }
  }

  private boolean isAwsAvailable() {
    return pipelinesClient != null;
  }

  private synchronized String getAwsAccountId() {
    if (cachedAccountId != null) {
      return cachedAccountId;
    }
    if (stsClient == null) {
      log.warn("STS client not available — cannot resolve AWS account ID");
      return null;
    }
    try {
      GetCallerIdentityResponse identity = stsClient.getCallerIdentity();
      cachedAccountId = identity.account();
      log.info("Resolved AWS account ID: {}", cachedAccountId);
      return cachedAccountId;
    } catch (Exception e) {
      if (log.isErrorEnabled()) {
        log.error("Failed to resolve AWS account ID via STS: {}", e.getMessage());
      }
      return null;
    }
  }

  private String normalizeCallId(String callId) {
    if (callId == null) {
      return null;
    }
    String trimmed = callId.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }
}

