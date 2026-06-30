package com.careconnect.service;

import com.careconnect.exception.KvsStreamPoolExhaustedException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * KVS configuration for per-attendee speaker capture.
 *
 * <p><strong>Ingest mode (F5.5):</strong> {@code careconnect.kvs.stream-pool-arn} points at a Chime
 * {@code media-pipeline-kinesis-video-stream-pool}. Meeting audio is written via
 * {@code CreateMediaStreamPipeline}; stream ARNs are resolved by {@link KvsAttendeeStreamResolver}.
 *
 * <p><strong>Legacy mode:</strong> {@code careconnect.kvs.stream-arns} lists manual pre-provisioned
 * KVS streams for in-app checkout (deprecated — insufficient for ingest alone).
 */
@Service
public class KvsStreamPoolService {

    private final boolean enabled;
    private final String streamPoolArn;
    private final List<String> legacyPoolArns;
    private final Map<String, Map<String, String>> reservationsByCall = new ConcurrentHashMap<>();
    private final Map<String, String> streamOwnerByArn = new ConcurrentHashMap<>();

    @Autowired
    public KvsStreamPoolService(
            @Value("${careconnect.kvs.enabled:false}") final boolean enabled,
            @Value("${careconnect.kvs.stream-pool-arn:}") final String streamPoolArn,
            @Value("${careconnect.kvs.stream-arns:}") final String streamArnsCsv) {
        this(enabled, streamPoolArn, parseArns(streamArnsCsv));
    }

    /** Visible for unit tests. */
    static KvsStreamPoolService forTest(
            final boolean enabled, final String streamPoolArn, final String streamArnsCsv) {
        return new KvsStreamPoolService(enabled, streamPoolArn, parseArns(streamArnsCsv));
    }

    /** Legacy test helper (manual stream ARNs only). */
    static KvsStreamPoolService forTest(final boolean enabled, final String streamArnsCsv) {
        return new KvsStreamPoolService(enabled, "", parseArns(streamArnsCsv));
    }

    private KvsStreamPoolService(
            final boolean enabled, final String streamPoolArn, final List<String> legacyPoolArns) {
        this.enabled = enabled;
        this.streamPoolArn = streamPoolArn == null ? "" : streamPoolArn.trim();
        this.legacyPoolArns = Collections.unmodifiableList(legacyPoolArns);
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

    /** Whether Chime media stream pipeline ingest is configured. */
    public boolean isIngestMode() {
        return enabled && !streamPoolArn.isBlank();
    }

    /** Whether legacy manual stream ARN checkout is configured. */
    public boolean isLegacyCheckoutMode() {
        return enabled && streamPoolArn.isBlank() && !legacyPoolArns.isEmpty();
    }

    /** Returns whether KVS speaker capture is configured (ingest or legacy checkout). */
    public boolean isEnabled() {
        return isIngestMode() || isLegacyCheckoutMode();
    }

    /** Total legacy manual streams in the configured list. */
    public int getPoolSize() {
        return legacyPoolArns.size();
    }

    /** Legacy manual streams not currently checked out. */
    public int getAvailableCount() {
        return (int) legacyPoolArns.stream().filter(arn -> !streamOwnerByArn.containsKey(arn)).count();
    }

    /**
     * Reserves a legacy manual KVS stream for a call participant.
     *
     * @param callId call identifier
     * @param holderId stable key for the reservation (e.g. Chime attendee id)
     * @return KVS stream ARN
     */
    public synchronized String checkout(final String callId, final String holderId) {
        if (!enabled) {
            throw new IllegalStateException("KVS stream pool is disabled");
        }
        if (!isLegacyCheckoutMode()) {
            if (isIngestMode()) {
                throw new IllegalStateException(
                        "Manual KVS stream checkout is not used when stream-pool-arn is configured");
            }
            throw new KvsStreamPoolExhaustedException("KVS stream pool is not configured");
        }
        if (legacyPoolArns.isEmpty()) {
            throw new KvsStreamPoolExhaustedException("KVS stream pool is not configured");
        }

        final Map<String, String> callReservations =
                reservationsByCall.computeIfAbsent(callId, ignored -> new HashMap<>());
        final String existing = callReservations.get(holderId);
        if (existing != null) {
            return existing;
        }

        final String arn =
                legacyPoolArns.stream()
                        .filter(candidate -> !streamOwnerByArn.containsKey(candidate))
                        .findFirst()
                        .orElseThrow(
                                () ->
                                        new KvsStreamPoolExhaustedException(
                                                "No KVS streams available in pool"));

        streamOwnerByArn.put(arn, callId);
        callReservations.put(holderId, arn);
        return arn;
    }

    /** Releases all legacy stream reservations for a call. */
    public synchronized void releaseCall(final String callId) {
        final Map<String, String> callReservations = reservationsByCall.remove(callId);
        if (callReservations == null) {
            return;
        }
        for (final String arn : callReservations.values()) {
            streamOwnerByArn.remove(arn, callId);
        }
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

    private static List<String> parseArns(final String streamArnsCsv) {
        if (streamArnsCsv == null || streamArnsCsv.isBlank()) {
            return List.of();
        }
        final List<String> arns = new ArrayList<>();
        for (final String part : streamArnsCsv.split(",")) {
            final String trimmed = part.trim();
            if (!trimmed.isEmpty()) {
                arns.add(trimmed);
            }
        }
        return arns;
    }
}
