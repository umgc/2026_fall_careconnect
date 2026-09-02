package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.User;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("CallAttendeeService Tests")
class CallAttendeeServiceTest {

    private static final String CALL_ID = "call-speaker-001";
    private static final String CHIME_ATTENDEE_ID = "chime-att-abc";
    private static final String OLD_CHIME_ATTENDEE_ID = "chime-att-old";
    private static final Long USER_ID = 42L;
    private static final String ROLE = "CAREGIVER";
    private static final String MEETING_ID = "meeting-uuid";

    @Mock
    private CallAttendeeRepository callAttendeeRepository;
    @Mock
    private CallParticipantRepository callParticipantRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private ChimeService chimeService;

    private CallAttendeeService service;

    @BeforeEach
    void setUp() {
        service = new CallAttendeeService(
                callAttendeeRepository, callParticipantRepository, userRepository, chimeService);
    }

    @Test
    @DisplayName("SPEAKER-003: recordJoin creates new attendee row with joined_at")
    void recordJoin_createsNewRow() {
        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of());
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.empty());
        when(callAttendeeRepository.save(any(CallAttendee.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final CallAttendee saved = service.recordJoin(CALL_ID, CHIME_ATTENDEE_ID, USER_ID, ROLE);

        assertThat(saved.getCallId()).isEqualTo(CALL_ID);
        assertThat(saved.getChimeAttendeeId()).isEqualTo(CHIME_ATTENDEE_ID);
        assertThat(saved.getUserId()).isEqualTo(USER_ID);
        assertThat(saved.getRole()).isEqualTo(ROLE);
        assertThat(saved.getJoinedAt()).isNotNull();
        assertThat(saved.getLeftAt()).isNull();
    }

    @Test
    @DisplayName("SPEAKER-004: recordJoin re-join upserts same row and clears left_at")
    void recordJoin_rejoinUpsertsExistingRow() {
        final CallAttendee existing = new CallAttendee();
        existing.setId(7L);
        existing.setCallId(CALL_ID);
        existing.setChimeAttendeeId(CHIME_ATTENDEE_ID);
        existing.setUserId(USER_ID);
        existing.setRole("PATIENT");
        existing.setJoinedAt(LocalDateTime.of(2026, 1, 1, 10, 0));
        existing.setLeftAt(LocalDateTime.of(2026, 1, 1, 10, 30));

        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of(existing));
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.of(existing));
        when(callAttendeeRepository.save(existing)).thenReturn(existing);

        final CallAttendee saved = service.recordJoin(CALL_ID, CHIME_ATTENDEE_ID, USER_ID, ROLE);

        assertThat(saved.getRole()).isEqualTo(ROLE);
        assertThat(saved.getLeftAt()).isNull();
        assertThat(saved.getJoinedAt()).isAfter(LocalDateTime.of(2026, 1, 1, 10, 0));
    }

    @Test
    @DisplayName("SPEAKER-O1: recordJoin supersedes stale chime_attendee_id for same user")
    void recordJoin_supersedesStaleAttendeeId() {
        final CallAttendee stale = new CallAttendee();
        stale.setCallId(CALL_ID);
        stale.setUserId(USER_ID);
        stale.setChimeAttendeeId(OLD_CHIME_ATTENDEE_ID);

        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of(stale));
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.empty());
        when(callAttendeeRepository.save(any(CallAttendee.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.recordJoin(CALL_ID, CHIME_ATTENDEE_ID, USER_ID, ROLE);

        assertThat(stale.getLeftAt()).isNotNull();
        verify(callAttendeeRepository).saveAll(List.of(stale));
    }

    @Test
    @DisplayName("recordJoinFromStreamEvent upserts roster from legacy externalUserId")
    void recordJoinFromStreamEvent_upsertsFromExternalUserId() {
        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, 2L))
                .thenReturn(List.of());
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.empty());
        when(callAttendeeRepository.save(any(CallAttendee.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.recordJoinFromStreamEvent(CALL_ID, CHIME_ATTENDEE_ID, "CAREGIVER_Test_2");

        verify(callAttendeeRepository).save(any(CallAttendee.class));
    }

    @Test
    @DisplayName("recordJoinFromStreamEvent resolves opaque UUID via call_participants")
    void recordJoinFromStreamEvent_resolvesOpaqueExternalUserId() {
        final String opaqueId = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
        final CallParticipant participant = new CallParticipant();
        participant.setUserId(USER_ID);
        participant.setChimeExternalUserId(opaqueId);
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.CAREGIVER);

        when(callParticipantRepository.findFirstByChimeExternalUserId(opaqueId))
                .thenReturn(Optional.of(participant));
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of());
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.empty());
        when(callAttendeeRepository.save(any(CallAttendee.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.recordJoinFromStreamEvent(CALL_ID, CHIME_ATTENDEE_ID, opaqueId);

        verify(callAttendeeRepository).save(any(CallAttendee.class));
    }

    @Test
    @DisplayName("recordJoinFromStreamEvent skips pipeline-internal externalUserId")
    void recordJoinFromStreamEvent_skipsPipelineInternal() {
        service.recordJoinFromStreamEvent(
                CALL_ID, CHIME_ATTENDEE_ID, "aws:MediaPipeline-abc");

        verify(callAttendeeRepository, never()).save(any());
    }

    @Test
    @DisplayName("recordKvsStreamMapping persists attendee stream ARN for F7 export")
    void recordKvsStreamMapping_persistsStreamArn() {
        final CallAttendee attendee = new CallAttendee();
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(CHIME_ATTENDEE_ID);
        final String streamArn = "arn:aws:kinesisvideo:us-east-1:1:stream/chime/1";
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.of(attendee));

        service.recordKvsStreamMapping(CALL_ID, CHIME_ATTENDEE_ID, streamArn);

        assertThat(attendee.getKvsStreamArn()).isEqualTo(streamArn);
        verify(callAttendeeRepository).save(attendee);
    }

    @Test
    @DisplayName("reconcileRosterFromChime syncs live ListAttendees and marks stale rows left")
    void reconcileRosterFromChime_syncsLiveAttendees() {
        when(chimeService.listMeetingAttendees(MEETING_ID))
                .thenReturn(
                        List.of(
                                new ChimeMeetingAttendee(
                                        CHIME_ATTENDEE_ID, "CAREGIVER_Test_" + USER_ID)));
        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of());
        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.empty());
        when(callAttendeeRepository.save(any(CallAttendee.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final CallAttendee stale = new CallAttendee();
        stale.setCallId(CALL_ID);
        stale.setChimeAttendeeId(OLD_CHIME_ATTENDEE_ID);
        stale.setUserId(99L);
        when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                .thenReturn(List.of(stale));

        service.reconcileRosterFromChime(CALL_ID, MEETING_ID);

        assertThat(stale.getLeftAt()).isNotNull();
        verify(callAttendeeRepository).saveAll(List.of(stale));
    }

    @Test
    @DisplayName("SPEAKER-005: recordLeave sets left_at on active rows for user")
    void recordLeave_setsLeftAtOnActiveRows() {
        final CallAttendee active = new CallAttendee();
        active.setCallId(CALL_ID);
        active.setUserId(USER_ID);
        active.setChimeAttendeeId(CHIME_ATTENDEE_ID);

        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of(active));

        service.recordLeave(CALL_ID, USER_ID);

        assertThat(active.getLeftAt()).isNotNull();
        verify(callAttendeeRepository).saveAll(List.of(active));
    }

    @Test
    @DisplayName("SPEAKER-006: recordLeave no-op when user has no active rows")
    void recordLeave_noActiveRows_noSave() {
        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of());

        service.recordLeave(CALL_ID, USER_ID);

        verify(callAttendeeRepository, never()).saveAll(any());
    }

    @Test
    @DisplayName("SPEAKER-O2: recordCallEnded sets left_at on all active attendee rows")
    void recordCallEnded_setsLeftAtOnAllActiveRows() {
        final CallAttendee caregiver = new CallAttendee();
        caregiver.setCallId(CALL_ID);
        caregiver.setUserId(2L);
        final CallAttendee patient = new CallAttendee();
        patient.setCallId(CALL_ID);
        patient.setUserId(1L);
        when(callAttendeeRepository.findByCallIdAndLeftAtIsNull(CALL_ID))
                .thenReturn(List.of(caregiver, patient));

        service.recordCallEnded(CALL_ID);

        assertThat(caregiver.getLeftAt()).isNotNull();
        assertThat(patient.getLeftAt()).isNotNull();
        verify(callAttendeeRepository).saveAll(List.of(caregiver, patient));
    }
}
