package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineStatus;

/**
 * Resolves Chime-assigned KVS stream ARNs for call attendees after a media stream pipeline starts.
 *
 * <p>Primary path: {@link KvsPoolStreamDiscoveryService} polls KVS pool streams and reads
 * fragment metadata. Optional fast-path: {@link KvsAttendeeStreamRegistry} pre-filled by EventBridge
 * webhook if configured.
 */
@Service
public class KvsAttendeeStreamResolver {

    private static final Logger log = LoggerFactory.getLogger(KvsAttendeeStreamResolver.class);

    private static final long DEFAULT_POLL_INTERVAL_MS = 3_000L;

    private final KvsAttendeeStreamRegistry registry;
    private final KvsPoolStreamDiscoveryService poolStreamDiscoveryService;
    private final KvsStreamPoolService kvsStreamPoolService;

    @Autowired(required = false)
    private ChimeSdkMediaPipelinesClient pipelinesClient;

    @Value("${careconnect.kvs.stream-discovery-timeout-ms:60000}")
    private long discoveryTimeoutMs;

    @Value("${careconnect.kvs.stream-discovery-poll-interval-ms:3000}")
    private long pollIntervalMs;

    public KvsAttendeeStreamResolver(
            final KvsAttendeeStreamRegistry registry,
            final KvsPoolStreamDiscoveryService poolStreamDiscoveryService,
            final KvsStreamPoolService kvsStreamPoolService) {
        this.registry = registry;
        this.poolStreamDiscoveryService = poolStreamDiscoveryService;
        this.kvsStreamPoolService = kvsStreamPoolService;
    }

    /**
     * Waits for and returns attendee→stream ARN mappings for the given active attendees.
     *
     * @throws IllegalStateException when mappings cannot be resolved within the timeout
     */
    public Map<String, String> resolve(
            final String callId,
            final List<CallAttendee> attendees,
            final String mediaStreamPipelineId,
            final String meetingId) {
        if (attendees == null || attendees.isEmpty()) {
            return Map.of();
        }

        final List<String> attendeeIds =
                attendees.stream()
                        .sorted(Comparator.comparing(CallAttendee::getJoinedAt))
                        .map(CallAttendee::getChimeAttendeeId)
                        .collect(Collectors.toList());

        final long deadline = System.currentTimeMillis() + discoveryTimeoutMs;
        if (log.isInfoEnabled()) {
            log.info(
                    "KVS stream discovery started callId={} meetingId={} timeoutMs={} pollIntervalMs={}"
                            + " attendees={}",
                    callId,
                    meetingId,
                    discoveryTimeoutMs,
                    pollIntervalMs > 0 ? pollIntervalMs : DEFAULT_POLL_INTERVAL_MS,
                    attendeeIds.size());
        }
        waitForMediaStreamPipelineReady(mediaStreamPipelineId, deadline);
        while (System.currentTimeMillis() < deadline) {
            if (hasAllMappings(callId, attendeeIds)) {
                return copyMappings(callId, attendeeIds);
            }
            if (kvsStreamPoolService.isIngestMode()) {
                poolStreamDiscoveryService.discoverAndRegister(callId, meetingId, attendeeIds);
            }
            if (hasAllMappings(callId, attendeeIds)) {
                return copyMappings(callId, attendeeIds);
            }
            sleep(pollIntervalMs > 0 ? pollIntervalMs : DEFAULT_POLL_INTERVAL_MS);
        }

        if (hasAllMappings(callId, attendeeIds)) {
            return copyMappings(callId, attendeeIds);
        }

        if (log.isWarnEnabled()) {
            log.warn(
                    "Timed out waiting for KVS stream assignments callId={} meetingId={}"
                            + " mediaStreamPipelineId={} mapped={}/{}",
                    callId,
                    meetingId,
                    mediaStreamPipelineId,
                    registry.getMappings(callId).size(),
                    attendeeIds.size());
        }
        throw new IllegalStateException(
                "Timed out waiting for KVS stream assignments for call "
                        + callId
                        + " (mediaStreamPipelineId="
                        + mediaStreamPipelineId
                        + "). Ensure media stream ingest is active and KVS ListStreams/ListFragments"
                        + " IAM is allowed, or register mappings via optional EventBridge webhook.");
    }

    private boolean hasAllMappings(final String callId, final List<String> attendeeIds) {
        for (final String attendeeId : attendeeIds) {
            if (registry.getStreamArn(callId, attendeeId) == null) {
                return false;
            }
        }
        return true;
    }

    private Map<String, String> copyMappings(final String callId, final List<String> attendeeIds) {
        final Map<String, String> resolved = new HashMap<>();
        for (final String attendeeId : attendeeIds) {
            resolved.put(attendeeId, registry.getStreamArn(callId, attendeeId));
        }
        return resolved;
    }

    private void waitForMediaStreamPipelineReady(
            final String mediaStreamPipelineId, final long discoveryDeadline) {
        if (pipelinesClient == null
                || mediaStreamPipelineId == null
                || mediaStreamPipelineId.isBlank()) {
            return;
        }
        final long pipelineWaitDeadline =
                Math.min(discoveryDeadline, System.currentTimeMillis() + 20_000L);
        MediaPipelineStatus lastStatus = null;
        while (System.currentTimeMillis() < pipelineWaitDeadline) {
            try {
                final var response =
                        pipelinesClient.getMediaPipeline(
                                GetMediaPipelineRequest.builder()
                                        .mediaPipelineId(mediaStreamPipelineId)
                                        .build());
                if (response.mediaPipeline() != null
                        && response.mediaPipeline().mediaStreamPipeline() != null) {
                    lastStatus = response.mediaPipeline().mediaStreamPipeline().status();
                    if (lastStatus == MediaPipelineStatus.IN_PROGRESS) {
                        if (log.isInfoEnabled()) {
                            log.info(
                                    "Media stream pipeline {} is InProgress — starting KVS discovery",
                                    mediaStreamPipelineId);
                        }
                        return;
                    }
                    if (lastStatus == MediaPipelineStatus.FAILED) {
                        if (log.isWarnEnabled()) {
                            log.warn(
                                    "Media stream pipeline {} failed — KVS streams will not appear",
                                    mediaStreamPipelineId);
                        }
                        return;
                    }
                }
            } catch (Exception e) {
                if (log.isDebugEnabled()) {
                    log.debug(
                            "Media stream pipeline {} not yet queryable: {}",
                            mediaStreamPipelineId,
                            e.getMessage());
                }
            }
            sleep(pollIntervalMs > 0 ? pollIntervalMs : DEFAULT_POLL_INTERVAL_MS);
        }
        if (log.isWarnEnabled()) {
            log.warn(
                    "Media stream pipeline {} not InProgress after wait (lastStatus={}) —"
                            + " discovery will continue but streams appear only after audio flows",
                    mediaStreamPipelineId,
                    lastStatus);
        }
    }

    private static void sleep(final long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
