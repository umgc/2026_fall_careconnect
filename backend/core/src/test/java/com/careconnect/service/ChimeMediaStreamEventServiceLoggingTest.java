package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

/**
 * Runs {@link ChimeMediaStreamEventService#handleEventDetail} with logging enabled across the
 * ignored-event guards, pipeline-internal streams and an unaligned roster.
 */
@DisplayName("ChimeMediaStreamEventService logged paths")
class ChimeMediaStreamEventServiceLoggingTest {

    private static final String EVENT = "chime:MediaPipelineKinesisVideoStreamStart";
    private static final String CALL_ID = "call-ev-1";
    private static final String ARN = "arn:aws:kinesisvideo:us-east-1:1:stream/s/1";

    private final Logger serviceLogger = (Logger) LoggerFactory.getLogger(ChimeMediaStreamEventService.class);
    private Level originalLevel;
    private KvsAttendeeStreamRegistry registry;
    private ChimeService chimeService;
    private CallAttendeeService callAttendeeService;
    private ChimeMediaStreamEventService service;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.DEBUG);
        registry = new KvsAttendeeStreamRegistry();
        chimeService = mock(ChimeService.class);
        callAttendeeService = mock(CallAttendeeService.class);
        service = new ChimeMediaStreamEventService(registry, chimeService, callAttendeeService);
    }

    @AfterEach
    void restore() {
        serviceLogger.setLevel(originalLevel);
    }

    private static Map<String, Object> detail(final String attendeeId, final String externalUserId) {
        final Map<String, Object> detail = new HashMap<>();
        detail.put("eventType", EVENT);
        detail.put("externalMeetingId", CALL_ID);
        detail.put("attendeeId", attendeeId);
        detail.put("kinesisVideoStreamArn", ARN);
        detail.put("externalUserId", externalUserId);
        return detail;
    }

    @Test
    @DisplayName("ignored events: empty, wrong type, missing ids, unresolved call, pipeline-internal")
    void ignoredEvents() {
        service.handleEventDetail(null);
        service.handleEventDetail(Map.of("eventType", "other"));
        service.handleEventDetail(Map.of("eventType", EVENT, "attendeeId", " "));
        final Map<String, Object> unresolved = detail("att-1", null);
        unresolved.remove("externalMeetingId");
        unresolved.put("meetingId", "m-1");
        service.handleEventDetail(unresolved);
        service.handleEventDetail(detail("att-1", "aws:MediaPipeline-1"));

        assertThat(registry.getMappings(CALL_ID)).isEmpty();
    }

    @Test
    @DisplayName("an event attendee not on the roster with no single orphan is logged as unaligned")
    void unalignedRoster_logged() {
        when(callAttendeeService.findActiveChimeAttendeeIds(CALL_ID)).thenReturn(List.of("roster-1", "roster-2"));

        service.handleEventDetail(detail("event-1", "ext-1"));

        assertThat(registry.getStreamArn(CALL_ID, "event-1")).isEqualTo(ARN);
    }

    @Test
    @DisplayName("a single orphan is aliased to the single roster row")
    void singleOrphan_aliased() {
        when(callAttendeeService.findActiveChimeAttendeeIds(CALL_ID)).thenReturn(List.of("roster-1"));

        service.handleEventDetail(detail("event-1", "ext-1"));

        assertThat(registry.getStreamArn(CALL_ID, "roster-1")).isEqualTo(ARN);
    }
}
