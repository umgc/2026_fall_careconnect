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
 * <p>Primary source is {@link KvsAttendeeStreamRegistry} (EventBridge or manual registration).
 * Polls until all attendees are mapped or the configured timeout elapses.
 */
@Service
public class KvsAttendeeStreamResolver {

    private static final Logger log = LoggerFactory.getLogger(KvsAttendeeStreamResolver.class);

    private static final long POLL_INTERVAL_MS = 500L;

    private final KvsAttendeeStreamRegistry registry;

    @Autowired(required = false)
    private ChimeSdkMediaPipelinesClient pipelinesClient;

    @Value("${careconnect.kvs.stream-discovery-timeout-ms:15000}")
    private long discoveryTimeoutMs;

    public KvsAttendeeStreamResolver(final KvsAttendeeStreamRegistry registry) {
        this.registry = registry;
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
        while (System.currentTimeMillis() < deadline) {
            waitForMediaStreamPipelineInProgress(mediaStreamPipelineId);
            if (hasAllMappings(callId, attendeeIds)) {
                return copyMappings(callId, attendeeIds);
            }
            sleep(POLL_INTERVAL_MS);
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
                        + "). Register mappings via EventBridge"
                        + " MediaPipelineKinesisVideoStreamStart or KvsAttendeeStreamRegistry.");
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

    private void waitForMediaStreamPipelineInProgress(final String mediaStreamPipelineId) {
        if (pipelinesClient == null
                || mediaStreamPipelineId == null
                || mediaStreamPipelineId.isBlank()) {
            return;
        }
        try {
            final var response =
                    pipelinesClient.getMediaPipeline(
                            GetMediaPipelineRequest.builder()
                                    .mediaPipelineId(mediaStreamPipelineId)
                                    .build());
            if (response.mediaPipeline() != null
                    && response.mediaPipeline().mediaStreamPipeline() != null
                    && response.mediaPipeline().mediaStreamPipeline().status()
                            == MediaPipelineStatus.IN_PROGRESS) {
                return;
            }
        } catch (Exception e) {
            if (log.isDebugEnabled()) {
                log.debug(
                        "Media stream pipeline {} not yet InProgress: {}",
                        mediaStreamPipelineId,
                        e.getMessage());
            }
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
