package com.careconnect.service;

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

    public ChimeMediaStreamEventService(
            final KvsAttendeeStreamRegistry registry, final ChimeService chimeService) {
        this.registry = registry;
        this.chimeService = chimeService;
    }

    /**
     * Processes an EventBridge {@code Chime Media Pipeline State Change} detail payload.
     *
     * @param detail EventBridge {@code detail} object
     */
    public void handleEventDetail(final Map<String, Object> detail) {
        if (detail == null || detail.isEmpty()) {
            return;
        }
        final Object eventType = detail.get("eventType");
        if (eventType == null || !EVENT_STREAM_START.equals(eventType.toString())) {
            return;
        }

        final String attendeeId = stringValue(detail.get("attendeeId"));
        final String streamArn = stringValue(detail.get("kinesisVideoStreamArn"));
        final String meetingId = stringValue(detail.get("meetingId"));
        if (attendeeId == null || streamArn == null || meetingId == null) {
            return;
        }

        final String callId = chimeService.findCallIdByMeetingId(meetingId);
        if (callId == null) {
            if (log.isDebugEnabled()) {
                log.debug(
                        "Ignoring KVS stream start for unknown meetingId={} attendeeId={}",
                        meetingId,
                        attendeeId);
            }
            return;
        }

        registry.register(callId, attendeeId, streamArn);
        if (log.isInfoEnabled()) {
            log.info(
                    "Registered KVS stream from EventBridge callId={} attendeeId={} streamArn={}",
                    callId,
                    attendeeId,
                    streamArn);
        }
    }

    private static String stringValue(final Object value) {
        if (value == null) {
            return null;
        }
        final String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }
}
