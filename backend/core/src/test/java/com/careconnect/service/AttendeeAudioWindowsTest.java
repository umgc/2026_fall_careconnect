package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.model.CallAttendee;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * Validates the per-attendee audio windows shared by voice screening and post-call
 * transcription: clamped to join/leave and to the recording (pool streams are reused across
 * calls), and consecutive per user so a rejoin never reads the same speech twice. Pure logic.
 */
class AttendeeAudioWindowsTest {

    private static final Long PATIENT = ConditionDetectionFixtures.PATIENT_USER_ID;
    private static final Long CAREGIVER = ConditionDetectionFixtures.CAREGIVER_USER_ID;
    /** A 10-minute recording; minutes below are offsets from its start. */
    private static final LocalDateTime REC_START = LocalDateTime.of(2026, 10, 24, 15, 0);
    private static final LocalDateTime REC_END = REC_START.plusMinutes(10);

    private static CallAttendee row(final long id, final Long user, final int joinMin, final Integer leftMin) {
        return ConditionDetectionFixtures.attendee(
                id, user, "arn:" + id, REC_START.plusMinutes(joinMin),
                leftMin == null ? null : REC_START.plusMinutes(leftMin));
    }

    /** Scenario: joined before recording started, never recorded a leave: clamped to the whole recording. */
    @Test
    void forUser_clampsToRecordingAndOpenLeave() {
        final List<AttendeeAudioWindows.Window> windows =
                AttendeeAudioWindows.forUser(List.of(row(1, PATIENT, -5, null)), REC_START, REC_END);

        assertThat(windows).singleElement().satisfies(w -> {
            assertThat(w.from()).isEqualTo(REC_START);
            assertThat(w.to()).isEqualTo(REC_END);
        });
    }

    /**
     * Scenario: a rapid rejoin whose leave was recorded late. Join 2 (min 3) happened before join
     * 1's leave (min 4) was written. Joining again ends the previous session, so join 1's window
     * stops at min 3 and the two never overlap.
     */
    @Test
    void forUser_lateRecordedLeave_isEndedByNextJoin() {
        // Arrange: deliberately unsorted.
        final List<CallAttendee> rows = List.of(row(2, PATIENT, 3, null), row(1, PATIENT, 1, 4));

        // Act
        final List<AttendeeAudioWindows.Window> windows = AttendeeAudioWindows.forUser(rows, REC_START, REC_END);

        // Assert
        assertThat(windows).extracting(w -> w.attendee().getId()).containsExactly(1L, 2L);
        assertThat(windows.get(0).to()).isEqualTo(REC_START.plusMinutes(3));
        assertThat(windows.get(1).from()).isEqualTo(REC_START.plusMinutes(3));
        assertThat(windows.get(1).to()).isEqualTo(REC_END);
    }

    /**
     * Scenario: a stale row whose leave was never recorded (null) followed by a newer join. The
     * stale stream may already be reassigned to another call, so it is read only until the newer
     * join, not to the end of the recording.
     */
    @Test
    void forUser_staleOpenRow_isEndedByNextJoin() {
        final List<AttendeeAudioWindows.Window> windows = AttendeeAudioWindows.forUser(
                List.of(row(1, PATIENT, 1, null), row(2, PATIENT, 5, null)), REC_START, REC_END);

        assertThat(windows).hasSize(2);
        assertThat(windows.get(0).to()).isEqualTo(REC_START.plusMinutes(5));
        assertThat(windows.get(1).to()).isEqualTo(REC_END);
    }

    /** Scenario: rows entirely outside the recording, or zero-length, produce no window. */
    @Test
    void forUser_rowsOutsideRecording_areDropped() {
        final List<CallAttendee> rows = List.of(row(1, PATIENT, -9, -2), row(2, PATIENT, 11, null), row(3, PATIENT, 4, 4));

        assertThat(AttendeeAudioWindows.forUser(rows, REC_START, REC_END)).isEmpty();
    }

    /** Scenario: two people speak at the same time; only the same user's windows are made consecutive. */
    @Test
    void forCall_differentUsersMayOverlap_andRowsWithoutUserAreIgnored() {
        final List<CallAttendee> rows = List.of(
                row(1, PATIENT, 0, null), row(2, CAREGIVER, 1, null), row(3, null, 0, null));

        final List<AttendeeAudioWindows.Window> windows = AttendeeAudioWindows.forCall(rows, REC_START, REC_END);

        assertThat(windows).extracting(w -> w.attendee().getId()).containsExactly(1L, 2L);
        assertThat(windows.get(1).from()).isEqualTo(REC_START.plusMinutes(1));
    }

    /** Scenario: the instant accessors read the stored local times as UTC. */
    @Test
    void window_instantsAreUtc() {
        final AttendeeAudioWindows.Window window =
                AttendeeAudioWindows.forUser(List.of(row(1, PATIENT, 0, 1)), REC_START, REC_END).get(0);

        assertThat(window.fromInstant()).hasToString("2026-10-24T15:00:00Z");
        assertThat(window.toInstant()).hasToString("2026-10-24T15:01:00Z");
    }
}
