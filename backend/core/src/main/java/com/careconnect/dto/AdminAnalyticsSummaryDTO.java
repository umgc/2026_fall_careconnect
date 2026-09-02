package com.careconnect.dto;

import java.time.Instant;
import java.util.List;

/**
 * Admin-facing anonymous product telemetry summary. Contains no PII/PHI.
 */
public record AdminAnalyticsSummaryDTO(
        Instant periodStart,
        Instant periodEnd,
        long totalEvents,
        long sessionCount,
        List<EventNameCountDTO> eventCountsByName,
        List<FeatureUsageCountDTO> topFeatures,
        SyncMetricsDTO syncMetrics,
        ErrorMetricsDTO errorMetrics) {
}
