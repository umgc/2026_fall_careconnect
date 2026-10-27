package com.careconnect.testsupport.fixtures;

import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallRecording;
import com.careconnect.model.CallSession;
import com.careconnect.model.User;
import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.model.conditiondetection.ConditionFlag;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionRunState;
import com.careconnect.security.Role;
import java.time.LocalDateTime;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Shared entity builders for AI condition detection tests.
 *
 * <p>Defaults describe one ordinary call: call id {@value #CALL_ID}, patient profile
 * {@value #PATIENT_ID} whose user id is {@value #PATIENT_USER_ID}, and a recording whose id is
 * {@value #RECORDING_ID}. Tests override only the field a scenario is about.</p>
 */
public final class ConditionDetectionFixtures {

    public static final String CALL_ID = "call-1";
    public static final Long PATIENT_ID = 7L;
    public static final Long PATIENT_USER_ID = 70L;
    public static final Long CAREGIVER_USER_ID = 80L;
    public static final Long RECORDING_ID = 55L;
    public static final String MODEL_ID = "kintsugi-dam-3.1";

    private ConditionDetectionFixtures() {
        // Utility class
    }

    /** A call session for {@link #PATIENT_ID}. */
    public static CallSession session() {
        final CallSession session = new CallSession();
        session.setPatientId(PATIENT_ID);
        return session;
    }

    /** A recording with the given duration (may be null) and no start/end times. */
    public static CallRecording recording(final Long durationSeconds) {
        final CallRecording recording = new CallRecording();
        recording.setId(RECORDING_ID);
        recording.setCallId(CALL_ID);
        recording.setDurationSeconds(durationSeconds);
        return recording;
    }

    /** A recording with explicit start/end times (end may be null while finalizing). */
    public static CallRecording recording(final LocalDateTime startedAt, final LocalDateTime endedAt) {
        final CallRecording recording = recording((Long) null);
        recording.setStartedAt(startedAt);
        recording.setEndedAt(endedAt);
        return recording;
    }

    /** One Chime join of {@code userId} with its KVS stream. */
    public static CallAttendee attendee(
            final long id, final Long userId, final String kvsStreamArn,
            final LocalDateTime joinedAt, final LocalDateTime leftAt) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setId(id);
        attendee.setCallId(CALL_ID);
        attendee.setUserId(userId);
        attendee.setKvsStreamArn(kvsStreamArn);
        attendee.setJoinedAt(joinedAt);
        attendee.setLeftAt(leftAt);
        return attendee;
    }

    /** A persisted-looking run for {@link #MODEL_ID} in the given state, one attempt used. */
    public static ConditionDetectionRun run(final long id, final String modelId, final ConditionRunState state) {
        final ConditionDetectionRun run = new ConditionDetectionRun();
        ReflectionTestUtils.setField(run, "id", id);
        run.setCallId(CALL_ID);
        run.setPatientId(PATIENT_ID);
        run.setPatientUserId(PATIENT_USER_ID);
        run.setModelId(modelId);
        run.setInputKind(ConditionInputKind.PATIENT_AUDIO);
        run.setState(state);
        run.setAttemptCount(1);
        run.setCreatedAt(LocalDateTime.of(2026, 10, 7, 12, 0));
        return run;
    }

    /** A flag belonging to run {@code runId}. */
    public static ConditionFlag flag(
            final long runId, final ConditionName name, final int level, final String label,
            final Double rawScore) {
        final ConditionFlag flag = new ConditionFlag();
        flag.setRunId(runId);
        flag.setCallId(CALL_ID);
        flag.setPatientId(PATIENT_ID);
        flag.setModelId(MODEL_ID);
        flag.setConditionName(name);
        flag.setSeverityLevel(level);
        flag.setSeverityLabel(label);
        flag.setRawScore(rawScore);
        return flag;
    }

    /** A user with the given id and role. */
    public static User user(final Long id, final Role role) {
        final User user = new User();
        user.setId(id);
        user.setRole(role);
        return user;
    }
}
