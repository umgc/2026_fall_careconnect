package com.careconnect.service;

import java.util.LinkedHashMap;
import java.util.Map;

/** Typed result for an owner-fenced recording stop attempt. */
public record RecordingStopResult(
        Status status,
        String callId,
        String pipelineId,
        String recordingStatus,
        String concatenationPipelineId,
        String concatenationStatus,
        String message) {

    public enum Status {
        STOPPED, ALREADY_STOPPED, NOT_RECORDING, RETRYABLE_FAILURE, FORBIDDEN
    }

    public Map<String, Object> toMap() {
        final Map<String, Object> result = new LinkedHashMap<>();
        result.put("status", status.name());
        put(result, "callId", callId);
        put(result, "pipelineId", pipelineId);
        put(result, "recordingStatus", recordingStatus);
        put(result, "concatenationPipelineId", concatenationPipelineId);
        put(result, "concatenationStatus", concatenationStatus);
        put(result, "message", message);
        return result;
    }

    private static void put(
            final Map<String, Object> target, final String key, final Object value) {
        if (value != null) {
            target.put(key, value);
        }
    }
}
