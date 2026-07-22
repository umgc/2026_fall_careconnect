package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import com.careconnect.repository.CallAttendeeRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
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
    private static final Long USER_ID = 42L;
    private static final String ROLE = "CAREGIVER";

    @Mock private CallAttendeeRepository callAttendeeRepository;

    private CallAttendeeService service;

    @BeforeEach
    void setUp() {
        service = new CallAttendeeService(callAttendeeRepository);
    }

    @Test
    @DisplayName("SPEAKER-003: recordJoin creates new attendee row with joined_at")
    void recordJoin_createsNewRow() {
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

        when(callAttendeeRepository.findByCallIdAndChimeAttendeeId(CALL_ID, CHIME_ATTENDEE_ID))
                .thenReturn(Optional.of(existing));
        when(callAttendeeRepository.save(existing)).thenReturn(existing);

        final CallAttendee saved = service.recordJoin(CALL_ID, CHIME_ATTENDEE_ID, USER_ID, ROLE);

        assertThat(saved.getRole()).isEqualTo(ROLE);
        assertThat(saved.getLeftAt()).isNull();
        assertThat(saved.getJoinedAt()).isAfter(LocalDateTime.of(2026, 1, 1, 10, 0));
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

        final ArgumentCaptor<List<CallAttendee>> captor = ArgumentCaptor.forClass(List.class);
        verify(callAttendeeRepository).saveAll(captor.capture());
        assertThat(captor.getValue().get(0).getLeftAt()).isNotNull();
    }

    @Test
    @DisplayName("SPEAKER-006: recordLeave no-op when user has no active rows")
    void recordLeave_noActiveRows_noSave() {
        when(callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, USER_ID))
                .thenReturn(List.of());

        service.recordLeave(CALL_ID, USER_ID);

        verify(callAttendeeRepository, never()).saveAll(any());
    }
}
