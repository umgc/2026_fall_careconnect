package com.careconnect.model.conditiondetection;

import java.time.LocalDateTime;

/**
 * What an adapter needs to locate its input for one run.
 *
 * @param callId          the call being analyzed
 * @param patientEntityId patients.id
 * @param patientUserId   the patient's users.id (matches attendee and transcript actor ids)
 * @param recordingId     the call's latest recording, or {@code null} if none
 * @param runCreatedAt    UTC time the run was enqueued; adapters use it for input deadlines
 */
public record ConditionDetectionContext(
        String callId,
        Long patientEntityId,
        Long patientUserId,
        Long recordingId,
        LocalDateTime runCreatedAt) {
}
