package com.careconnect.service;

import java.util.Collections;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * In-memory attendee→KVS stream ARN mappings for active calls.
 *
 * <p>Populated by {@link KvsAttendeeStreamResolver} (fragment discovery) or future EventBridge
 * handlers when Chime emits {@code MediaPipelineKinesisVideoStreamStart} events.
 */
@Component
public class KvsAttendeeStreamRegistry {

    private final Map<String, Map<String, String>> streamArnByAttendeeByCall =
            new ConcurrentHashMap<>();

    /** Records a Chime-assigned KVS stream for an attendee on a call. */
    public void register(final String callId, final String chimeAttendeeId, final String streamArn) {
        if (callId == null
                || callId.isBlank()
                || chimeAttendeeId == null
                || chimeAttendeeId.isBlank()
                || streamArn == null
                || streamArn.isBlank()) {
            return;
        }
        streamArnByAttendeeByCall
                .computeIfAbsent(callId, ignored -> new ConcurrentHashMap<>())
                .put(chimeAttendeeId, streamArn);
    }

    /** Returns the mapped stream ARN, or {@code null} when unknown. */
    public String getStreamArn(final String callId, final String chimeAttendeeId) {
        final Map<String, String> callMappings = streamArnByAttendeeByCall.get(callId);
        if (callMappings == null) {
            return null;
        }
        return callMappings.get(chimeAttendeeId);
    }

    /** Returns an unmodifiable view of attendee→stream mappings for a call. */
    public Map<String, String> getMappings(final String callId) {
        final Map<String, String> callMappings = streamArnByAttendeeByCall.get(callId);
        if (callMappings == null || callMappings.isEmpty()) {
            return Map.of();
        }
        return Collections.unmodifiableMap(callMappings);
    }

    /** Clears all mappings for a call (e.g. on call end). */
    public void clearCall(final String callId) {
        if (callId == null || callId.isBlank()) {
            return;
        }
        streamArnByAttendeeByCall.remove(callId);
    }
}
