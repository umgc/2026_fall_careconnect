package com.careconnect.service;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("ChimeMediaStreamEventService Tests")
class ChimeMediaStreamEventServiceTest {

    private static final String CALL_ID = "chime_call_1783033207169";
    private static final String MEETING_ID = "a83811e4-f0da-44b0-b1e3-49100df42713";
    private static final String EVENT_ATTENDEE_ID = "9d94cbf4-3afc-9ac3-4974-c116336f4dbc";
    private static final String ROSTER_ATTENDEE_ID = "9815dabc-1111-2222-3333-444444444444";
    private static final String STREAM_ARN =
            "arn:aws:kinesisvideo:us-east-1:123:stream/ChimeMediaPipelines-test/1";

    @Mock
    private ChimeService chimeService;
    @Mock
    private CallAttendeeService callAttendeeService;

    private KvsAttendeeStreamRegistry registry;
    private ChimeMediaStreamEventService service;

    private static Map<String, Object> streamStartDetail(
            final String attendeeId, final String externalUserId) {
        final Map<String, Object> detail =
                new java.util.HashMap<>(
                        Map.of(
                                "eventType",
                                "chime:MediaPipelineKinesisVideoStreamStart",
                                "meetingId",
                                MEETING_ID,
                                "externalMeetingId",
                                CALL_ID,
                                "attendeeId",
                                attendeeId,
                                "kinesisVideoStreamArn",
                                STREAM_ARN));
        if (externalUserId != null) {
            detail.put("externalUserId", externalUserId);
        }
        return detail;
    }

    @BeforeEach
    void setUp() {
        registry = new KvsAttendeeStreamRegistry();
        service = new ChimeMediaStreamEventService(registry, chimeService, callAttendeeService);
    }

    @Test
    @DisplayName("registers stream using externalMeetingId as callId")
    void handleEventDetail_usesExternalMeetingId() {
        when(callAttendeeService.findActiveChimeAttendeeIds(CALL_ID))
                .thenReturn(List.of(EVENT_ATTENDEE_ID));

        service.handleEventDetail(streamStartDetail(EVENT_ATTENDEE_ID, null));

        assertThat(registry.getStreamArn(CALL_ID, EVENT_ATTENDEE_ID)).isEqualTo(STREAM_ARN);
        verify(chimeService, never()).findCallIdByMeetingId(anyString());
        verify(callAttendeeService).reconcileRosterFromChime(CALL_ID, MEETING_ID);
    }

    @Test
    @DisplayName("falls back to meetingId lookup when externalMeetingId absent")
    void handleEventDetail_fallsBackToMeetingLookup() {
        final Map<String, Object> detail = streamStartDetail(EVENT_ATTENDEE_ID, null);
        detail.remove("externalMeetingId");
        when(chimeService.findCallIdByMeetingId(MEETING_ID)).thenReturn(CALL_ID);
        when(callAttendeeService.findActiveChimeAttendeeIds(CALL_ID))
                .thenReturn(List.of(EVENT_ATTENDEE_ID));

        service.handleEventDetail(detail);

        assertThat(registry.getStreamArn(CALL_ID, EVENT_ATTENDEE_ID)).isEqualTo(STREAM_ARN);
        verify(chimeService).findCallIdByMeetingId(MEETING_ID);
    }

    @Test
    @DisplayName("aliases orphan EventBridge attendee id to single roster row (O1)")
    void handleEventDetail_aliasesOrphanToRoster() {
        when(callAttendeeService.findActiveChimeAttendeeIds(CALL_ID))
                .thenReturn(List.of(ROSTER_ATTENDEE_ID));

        service.handleEventDetail(
                streamStartDetail(EVENT_ATTENDEE_ID, "CAREGIVER_Test_2"));

        assertThat(registry.getStreamArn(CALL_ID, EVENT_ATTENDEE_ID)).isEqualTo(STREAM_ARN);
        assertThat(registry.getStreamArn(CALL_ID, ROSTER_ATTENDEE_ID)).isEqualTo(STREAM_ARN);
        verify(callAttendeeService)
                .recordJoinFromStreamEvent(CALL_ID, EVENT_ATTENDEE_ID, "CAREGIVER_Test_2");
    }

    @Test
    @DisplayName("ignores aws:MediaPipeline-* streams so they are not orphan-aliased to patient")
    void handleEventDetail_ignoresPipelineInternalExternalUserId() {
        service.handleEventDetail(
                streamStartDetail(EVENT_ATTENDEE_ID, "aws:MediaPipeline-99ebf"));

        assertThat(registry.getMappings(CALL_ID)).isEmpty();
        verify(callAttendeeService, never()).reconcileRosterFromChime(anyString(), anyString());
        verify(callAttendeeService, never())
                .recordJoinFromStreamEvent(anyString(), anyString(), anyString());
        verify(callAttendeeService, never()).findActiveChimeAttendeeIds(anyString());
    }
}
