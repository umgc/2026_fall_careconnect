package com.careconnect.dto;

/**
 * Aggregated offline-sync telemetry metrics.
 *
 * <p>{@code successRate} is {@code succeeded / (succeeded + failed)} using sums from
 * sync_completed event details. Returns null when the denominator is zero.
 */
public record SyncMetricsDTO(
        long started,
        long completed,
        long failedEvents,
        long attempted,
        long succeeded,
        long failed,
        Double successRate) {
}
