package com.careconnect.dto;

import java.time.Instant;
import java.util.List;

/** Daily feature_use trend for a single feature over a telemetry window. */
public record FeatureTrendDTO(
    String feature,
    Instant periodStart,
    Instant periodEnd,
    List<DailyFeatureCountDTO> dailyCounts) {}
