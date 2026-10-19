package com.careconnect.service;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Typed result for recording acquisition and AWS capture creation.
 */
public record RecordingStartResult(
        Status status,
        String callId,
        Long recordingId,
        long generation,
        String pipelineId,
        String s3Bucket,
        String s3Prefix,
        LocalDateTime startedAt,
        String message) {

    private static void put(
            final Map<String, Object> target, final String key, final Object value) {
        if (value != null) {
            target.put(key, value);
        }
    }

    public Map<String, Object> toMap() {
        final Map<String, Object> result = new LinkedHashMap<>();
        result.put("status", status.name());
        put(result, "callId", callId);
        put(result, "recordingId", recordingId);
        if (generation > 0) {
            result.put("generation", generation);
        }
        put(result, "pipelineId", pipelineId);
        put(result, "s3Bucket", s3Bucket);
        put(result, "s3Prefix", s3Prefix);
        put(result, "startedAt", startedAt == null ? null : startedAt.toString());
        put(result, "message", message);
        return result;
    }

    public enum Status {
        STARTED, ALREADY_RECORDING, POLICY_BLOCKED, DISABLED, UNAVAILABLE, ERROR
    }
}
