package com.careconnect.service;

import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Handles Chime media stream pipeline EventBridge notifications (e.g.
 * {@code chime:MediaPipelineKinesisVideoStreamStart}) and registers attendee→KVS stream mappings.
 */
@Service
public class ChimeMediaStreamEventService {

    private static final Logger log = LoggerFactory.getLogger(ChimeMediaStreamEventService.class);

    private static final String EVENT_STREAM_START = "chime:MediaPipelineKinesisVideoStreamStart";

    private final KvsAttendeeStreamRegistry registry;
    private final ChimeService chimeService;
    private final CallAttendeeService callAttendeeService;

    public ChimeMediaStreamEventService(
            final KvsAttendeeStreamRegistry registry,
            final ChimeService chimeService,
            final CallAttendeeService callAttendeeService) {
        this.registry = registry;
        this.chimeService = chimeService;
        this.callAttendeeService = callAttendeeService;
    }

    /**
     * Processes an EventBridge {@code Chime Media Pipeline State Change} detail payload.
     *
     * @param detail EventBridge {@code detail} object
     */
    public void handleEventDetail(final Map<String, Object> detail) {
        if (detail == null || detail.isEmpty()) {
            if (log.isWarnEnabled()) {
                log.warn("Ignoring KVS stream start — empty EventBridge detail payload");
            }
            return;
        }
        final Object eventType = detail.get("eventType");
        if (eventType == null || !EVENT_STREAM_START.equals(eventType.toString())) {
            if (log.isDebugEnabled()) {
                log.debug(
                        "Ignoring KVS stream start — eventType={} (expected {})",
                        eventType,
                        EVENT_STREAM_START);
            }
            return;
        }

        final String attendeeId = stringValue(detail.get("attendeeId"));
        final String streamArn = stringValue(detail.get("kinesisVideoStreamArn"));
        final String meetingId = stringValue(detail.get("meetingId"));
        final String externalMeetingId = stringValue(detail.get("externalMeetingId"));
        final String externalUserId = stringValue(detail.get("externalUserId"));
        if (attendeeId == null || streamArn == null) {
            if (log.isWarnEnabled()) {
                log.warn(
                        "Ignoring KVS stream start — missing attendeeId or kinesisVideoStreamArn"
                                + " (meetingId={} externalMeetingId={})",
                        meetingId,
                        externalMeetingId);
            }
            return;
        }

        final String callId = resolveCallId(externalMeetingId, meetingId);
        if (callId == null) {
            if (log.isWarnEnabled()) {
                log.warn(
                        "Ignoring KVS stream start — could not resolve callId from"
                                + " externalMeetingId={} meetingId={} attendeeId={}",
                        externalMeetingId,
                        meetingId,
                        attendeeId);
            }
            return;
        }

        if (meetingId != null) {
            callAttendeeService.reconcileRosterFromChime(callId, meetingId);
        }
        callAttendeeService.recordJoinFromStreamEvent(callId, attendeeId, externalUserId);

        registry.register(callId, attendeeId, streamArn);
        aliasStreamToRosterAttendees(callId, attendeeId, streamArn);
        persistRosterStreamMappings(callId);

        if (log.isInfoEnabled()) {
            log.info(
                    "Registered KVS stream from EventBridge callId={} attendeeId={} streamArn={}"
                            + " externalUserId={} externalMeetingId={}",
                    callId,
                    attendeeId,
                    streamArn,
                    externalUserId,
                    externalMeetingId);
        }
    }

    private void persistRosterStreamMappings(final String callId) {
        for (final String rosterAttendeeId : callAttendeeService.findActiveChimeAttendeeIds(callId)) {
            final String mappedStreamArn = registry.getStreamArn(callId, rosterAttendeeId);
            if (mappedStreamArn != null && !mappedStreamArn.isBlank()) {
                callAttendeeService.recordKvsStreamMapping(callId, rosterAttendeeId, mappedStreamArn);
            }
        }
    }

    /**
     * When EventBridge attendee id differs from roster id, alias the stream to the single unmatched
     * roster row (avoids mis-pairing when multiple orphans exist).
     */
    private void aliasStreamToRosterAttendees(
            final String callId, final String eventAttendeeId, final String streamArn) {
        final List<String> rosterIds = callAttendeeService.findActiveChimeAttendeeIds(callId);
        if (rosterIds.contains(eventAttendeeId)) {
            return;
        }
        if (registry.tryAliasOrphansToRoster(callId, rosterIds)) {
            if (log.isInfoEnabled()) {
                log.info(
                        "Aliased KVS stream callId={} from EventBridge attendeeId={} to roster",
                        callId,
                        eventAttendeeId);
            }
        } else if (log.isWarnEnabled() && !rosterIds.isEmpty()) {
            final List<String> rosterWithoutStream =
                    rosterIds.stream()
                            .filter(id -> registry.getStreamArn(callId, id) == null)
                            .toList();
            final List<String> orphanRegistryIds =
                    registry.getMappings(callId).keySet().stream()
                            .filter(id -> !rosterIds.contains(id))
                            .toList();
            log.warn(
                    "EventBridge attendeeId={} not aligned to roster callId={}; active roster={}"
                            + " rosterWithoutStream={} orphanRegistryIds={}",
                    eventAttendeeId,
                    callId,
                    rosterIds,
                    rosterWithoutStream,
                    orphanRegistryIds);
        }
    }

    private String resolveCallId(final String externalMeetingId, final String meetingId) {
        final String fromExternal = stringValue(externalMeetingId);
        if (fromExternal != null) {
            return fromExternal;
        }
        return chimeService.findCallIdByMeetingId(meetingId);
    }

    private static String stringValue(final Object value) {
        if (value == null) {
            return null;
        }
        final String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }
}
