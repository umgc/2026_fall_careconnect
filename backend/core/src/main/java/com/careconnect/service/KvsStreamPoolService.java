package com.careconnect.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger log = LoggerFactory.getLogger(KvsStreamPoolService.class);

    /** Resource segment identifying a Chime KVS stream-pool ARN. */
    private static final String STREAM_POOL_ARN_RESOURCE =
            ":media-pipeline-kinesis-video-stream-pool/";

    private final boolean enabled;
    private final String streamPoolArn;

    @Autowired
    public KvsStreamPoolService(
            @Value("${careconnect.kvs.enabled:false}") final boolean enabled,
            @Value("${careconnect.kvs.stream-pool-arn:}") final String streamPoolArn) {
        this.enabled = enabled;
        this.streamPoolArn = streamPoolArn == null ? "" : streamPoolArn.trim();
        if (enabled && !isWellFormedStreamPoolArn(this.streamPoolArn)) {
            log.warn(
                    "careconnect.kvs.enabled=true but careconnect.kvs.stream-pool-arn is missing or"
                            + " not a valid Chime media-pipeline-kinesis-video-stream-pool ARN"
                            + " (value='{}'); KVS speaker capture will not run until the SSM"
                            + " parameter is set to a real pool ARN.",
                    this.streamPoolArn);
        }
    }

    /** Visible for unit tests. */
    static KvsStreamPoolService forTest(final boolean enabled, final String streamPoolArn) {
        return new KvsStreamPoolService(enabled, streamPoolArn);
    }

    /** Chime KVS Stream Pool ARN used as the sink for {@code CreateMediaStreamPipeline}. */
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

    /** AWS region from the Chime stream pool ARN, or empty when not configured. */
    public String getStreamPoolRegion() {
        return extractArnRegion(streamPoolArn);
    }

    /** Whether Chime media stream pipeline ingest is configured with a usable pool ARN. */
    public boolean isIngestMode() {
        return enabled && isWellFormedStreamPoolArn(streamPoolArn);
    }

    /** Returns whether KVS speaker capture ingest is configured. */
    public boolean isEnabled() {
        return isIngestMode();
    }

    /**
     * True when {@code arn} looks like a real Chime {@code
     * media-pipeline-kinesis-video-stream-pool} ARN rather than blank or a placeholder value
     * (e.g. the CloudFormation-provisioned {@code REPLACE_WITH_CHIME_KVS_STREAM_POOL_ARN}
     * default, which is non-blank but not a usable ARN).
     */
    static boolean isWellFormedStreamPoolArn(final String arn) {
        if (arn == null || arn.isBlank()) {
            return false;
        }
        final String trimmed = arn.trim();
        return trimmed.startsWith("arn:")
                && trimmed.contains(STREAM_POOL_ARN_RESOURCE)
                && !extractArnRegion(trimmed).isBlank()
                && !extractResourceName(trimmed).isBlank();
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
}
