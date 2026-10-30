package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.model.CallAttendee;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.UserRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

/**
 * Happy-path roster reconcile, stream-event upsert, superseding and leave/end bookkeeping for
 * {@link CallAttendeeService}, with logging enabled. Repositories and Chime are mocks.
 */
@DisplayName("CallAttendeeService roster bookkeeping")
class CallAttendeeServiceRosterTest {

    private static final String CALL_ID = "call-roster-1";

    private final Logger serviceLogger = (Logger) LoggerFactory.getLogger(CallAttendeeService.class);
    private Level originalLevel;
    private CallAttendeeRepository attendees;
    private ChimeService chime;
    private CallAttendeeService service;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.INFO);
        attendees = mock(CallAttendeeRepository.class);
        chime = mock(ChimeService.class);
        final CallParticipantRepository participants = mock(CallParticipantRepository.class);
        when(participants.findFirstByChimeExternalUserId(anyString())).thenReturn(Optional.empty());
        when(attendees.findByCallIdAndChimeAttendeeId(anyString(), anyString())).thenReturn(Optional.empty());
        when(attendees.save(any(CallAttendee.class))).thenAnswer(inv -> inv.getArgument(0));
        service = new CallAttendeeService(attendees, participants, mock(UserRepository.class), chime);
    }

    @AfterEach
    void restore() {
        serviceLogger.setLevel(originalLevel);
    }

    private static CallAttendee row(final String chimeId, final Long userId) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(chimeId);
        attendee.setUserId(userId);
        return attendee;
    }

    @Test
    @DisplayName("reconcile upserts live app attendees and marks stale rows left")
    void reconcile_upsertsAndMarksLeft() {
        when(chime.listMeetingAttendees("m-1"))
                .thenReturn(List.of(
                        new ChimeMeetingAttendee("live-1", "ROLE_PATIENT_7"),
                        new ChimeMeetingAttendee(" ", "ROLE_PATIENT_8"),
                        new ChimeMeetingAttendee("pipe", "aws:MediaPipeline-1"),
                        new ChimeMeetingAttendee("unknown", "nobody")));
        final CallAttendee stale = row("stale-1", 7L);
        when(attendees.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, 7L)).thenReturn(List.of(stale));
        when(attendees.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(List.of(stale, row("live-1", 7L)));

        service.reconcileRosterFromChime(CALL_ID, "m-1");

        assertThat(stale.getLeftAt()).isNotNull();
        verify(attendees, org.mockito.Mockito.atLeastOnce()).saveAll(any());
    }

    @Test
    @DisplayName("reconcile skips blank input, empty rosters and rosters without app attendees")
    void reconcile_skips() {
        service.reconcileRosterFromChime(null, "m-1");
        service.reconcileRosterFromChime(CALL_ID, " ");
        when(chime.listMeetingAttendees("m-empty")).thenReturn(List.of());
        service.reconcileRosterFromChime(CALL_ID, "m-empty");
        when(chime.listMeetingAttendees("m-pipe")).thenReturn(List.of(new ChimeMeetingAttendee("p", "aws:x")));
        service.reconcileRosterFromChime(CALL_ID, "m-pipe");

        verify(attendees, never()).findByCallIdAndLeftAtIsNull(CALL_ID);
    }

    @Test
    @DisplayName("stream events upsert legacy users; unknown ids are ignored")
    void streamEvent_upserts() {
        service.recordJoinFromStreamEvent(CALL_ID, "att-1", "ROLE_CAREGIVER_9");
        service.recordJoinFromStreamEvent(CALL_ID, "att-2", "not-parseable");
        service.recordJoinFromStreamEvent(CALL_ID, "att-3", null);

        verify(attendees).save(any(CallAttendee.class));
    }

    @Test
    @DisplayName("kvs mappings, leave and call-end update active rows")
    void mappingsLeaveAndEnd() {
        final CallAttendee attendee = row("att-1", 7L);
        when(attendees.findByCallIdAndChimeAttendeeId(CALL_ID, "att-1")).thenReturn(Optional.of(attendee));
        service.recordKvsStreamMapping(CALL_ID, "att-1", "arn:s");
        service.recordKvsStreamMapping(CALL_ID, " ", "arn:s");
        assertThat(attendee.getKvsStreamArn()).isEqualTo("arn:s");

        when(attendees.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, 7L)).thenReturn(List.of(attendee));
        service.recordLeave(CALL_ID, 7L);
        when(attendees.findByCallIdAndLeftAtIsNull(CALL_ID)).thenReturn(List.of(row("att-2", 8L)));
        service.recordCallEnded(CALL_ID);
        service.recordCallEnded(" ");
        assertThat(service.findActiveChimeAttendeeIds(CALL_ID)).containsExactly("att-2");
        assertThat(attendee.getLeftAt()).isNotNull();
    }
}
