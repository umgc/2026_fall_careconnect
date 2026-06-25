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
 * Checks out pre-provisioned Kinesis Video Stream ARNs for per-attendee speaker capture.
 *
 * <p>Stream ARNs are provisioned via CloudFormation ({@code cloudformation-fargate}) and supplied
 * to the app as {@code careconnect.kvs.stream-arns} (comma-separated) or SSM in deployed envs.
 */
@Service
public class KvsStreamPoolService {

    private final boolean enabled;
    private final List<String> poolArns;
    private final Map<String, Map<String, String>> reservationsByCall = new ConcurrentHashMap<>();
    private final Map<String, String> streamOwnerByArn = new ConcurrentHashMap<>();

    @Autowired
    public KvsStreamPoolService(
            @Value("${careconnect.kvs.enabled:false}") final boolean enabled,
            @Value("${careconnect.kvs.stream-arns:}") final String streamArnsCsv) {
        this(enabled, parseArns(streamArnsCsv));
    }

    /** Visible for unit tests. */
    static KvsStreamPoolService forTest(final boolean enabled, final String streamArnsCsv) {
        return new KvsStreamPoolService(enabled, parseArns(streamArnsCsv));
    }

    private KvsStreamPoolService(final boolean enabled, final List<String> poolArns) {
        this.enabled = enabled;
        this.poolArns = Collections.unmodifiableList(poolArns);
    }

    /** Returns whether KVS checkout is configured and active. */
    public boolean isEnabled() {
        return enabled && !poolArns.isEmpty();
    }

    /** Total streams in the configured pool. */
    public int getPoolSize() {
        return poolArns.size();
    }

    /** Streams not currently checked out. */
    public int getAvailableCount() {
        return (int) poolArns.stream().filter(arn -> !streamOwnerByArn.containsKey(arn)).count();
    }

    /**
     * Reserves a KVS stream for a call participant.
     *
     * @param callId call identifier
     * @param holderId stable key for the reservation (e.g. Chime attendee id)
     * @return KVS stream ARN
     */
    public synchronized String checkout(final String callId, final String holderId) {
        if (!enabled) {
            throw new IllegalStateException("KVS stream pool is disabled");
        }
        if (poolArns.isEmpty()) {
            throw new KvsStreamPoolExhaustedException("KVS stream pool is not configured");
        }

        final Map<String, String> callReservations =
                reservationsByCall.computeIfAbsent(callId, ignored -> new HashMap<>());
        final String existing = callReservations.get(holderId);
        if (existing != null) {
            return existing;
        }

        final String arn =
                poolArns.stream()
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

    /** Releases all stream reservations for a call. */
    public synchronized void releaseCall(final String callId) {
        final Map<String, String> callReservations = reservationsByCall.remove(callId);
        if (callReservations == null) {
            return;
        }
        for (final String arn : callReservations.values()) {
            streamOwnerByArn.remove(arn, callId);
        }
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
