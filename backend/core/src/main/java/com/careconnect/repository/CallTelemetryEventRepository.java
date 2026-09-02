package com.careconnect.repository;

import com.careconnect.model.CallTelemetryEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

public interface CallTelemetryEventRepository
        extends JpaRepository<CallTelemetryEvent, Long> {

    /**
     * Returns call telemetry events for a call, newest first.
     *
     * @param callId call identifier
     * @return matching events in
     * descending occurrence order
     */
    List<CallTelemetryEvent> findByCallIdOrderByOccurredAtDesc(String callId);

    /**
     * Returns call telemetry events for a call, oldest first.
     *
     * @param callId call identifier
     * @return matching events in
     * ascending occurrence order
     */
    List<CallTelemetryEvent> findByCallIdOrderByOccurredAtAsc(String callId);

    /**
     * Returns up to 500 user-related telemetry events.
     *
     * @param actorUserId  actor user identifier
     * @param targetUserId target user identifier
     * @return matching events in
     * descending occurrence order
     */
    List<CallTelemetryEvent>
    findTop500ByActorUserIdOrTargetUserIdOrderByOccurredAtDesc(
            Long actorUserId,
            Long targetUserId
    );

    /**
     * Returns user-related telemetry events, oldest first.
     *
     * @param actorUserId  actor user identifier
     * @param targetUserId target user identifier
     * @return matching events in
     * ascending occurrence order
     */
    List<CallTelemetryEvent>
    findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(
            Long actorUserId,
            Long targetUserId
    );

    /**
     * Deletes telemetry events for a call.
     *
     * @param callId call identifier
     * @return number of deleted rows
     */
    @Modifying
    @Transactional
    long deleteByCallId(String callId);
}
