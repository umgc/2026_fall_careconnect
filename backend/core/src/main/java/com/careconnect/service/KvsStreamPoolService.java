package com.careconnect.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * KVS configuration for per-attendee speaker capture.
 *
 * <p>Requires {@code careconnect.kvs.stream-pool-arn} pointing at a Chime {@code
 * media-pipeline-kinesis-video-stream-pool}. Meeting audio is written via {@code
 * CreateMediaStreamPipeline}; stream ARNs are resolved by {@link KvsAttendeeStreamResolver}.
 */
@Service
public class KvsStreamPoolService {

    private final boolean enabled;
    private final String streamPoolArn;

    @Autowired
    public KvsStreamPoolService(
            @Value("${careconnect.kvs.enabled:false}") final boolean enabled,
            @Value("${careconnect.kvs.stream-pool-arn:}") final String streamPoolArn) {
        this.enabled = enabled;
        this.streamPoolArn = streamPoolArn == null ? "" : streamPoolArn.trim();
    }

    /**
     * Visible for unit tests.
     */
    static KvsStreamPoolService forTest(final boolean enabled, final String streamPoolArn) {
        return new KvsStreamPoolService(enabled, streamPoolArn);
    }

    static String extractResourceName(final String arn) {
        if (arn == null || arn.isBlank()) {
            return "";
        }
        final int slash = arn.lastIndexOf('/');
        return slash >= 0 && slash < arn.length() - 1 ? arn.substring(slash + 1) : "";
    }

    static String extractArnRegion(final String arn) {
        if (arn == null || arn.isBlank()) {
            return "";
        }
        final String[] parts = arn.split(":");
        return parts.length > 3 ? parts[3] : "";
    }

    /**
     * Chime KVS Stream Pool ARN used as the sink for {@code CreateMediaStreamPipeline}.
     */
    public String getStreamPoolArn() {
        return streamPoolArn;
    }

    /**
     * Pool name segment from a Chime {@code media-pipeline-kinesis-video-stream-pool} ARN
     * (e.g. {@code careconnect-dev-speaker}).
     */
    public String getStreamPoolName() {
        return extractResourceName(streamPoolArn);
    }

    /**
     * {@code ListStreams} name prefix for streams Chime creates in the pool. Actual names look like
     * {@code ChimeMediaPipelines-{poolName}-{uuid...}}, not {@code {poolName}} alone.
     */
    public String getStreamPoolListStreamsPrefix() {
        final String poolName = getStreamPoolName();
        if (poolName.isBlank()) {
            return "";
        }
        return "ChimeMediaPipelines-" + poolName;
    }

    /**
     * AWS region from the Chime stream pool ARN, or empty when not configured.
     */
    public String getStreamPoolRegion() {
        return extractArnRegion(streamPoolArn);
    }

    /**
     * Whether Chime media stream pipeline ingest is configured.
     */
    public boolean isIngestMode() {
        return enabled && !streamPoolArn.isBlank();
    }

    /**
     * Returns whether KVS speaker capture ingest is configured.
     */
    public boolean isEnabled() {
        return isIngestMode();
    }
}
