package com.careconnect.dto;

/**
 * Anonymous feature usage count from feature_use telemetry.
 */
public record FeatureUsageCountDTO(String feature, long count) {
}
