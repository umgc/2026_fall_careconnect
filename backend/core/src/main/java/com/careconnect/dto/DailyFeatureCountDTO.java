package com.careconnect.dto;

/**
 * Anonymous daily feature_use count for trend charts.
 */
public record DailyFeatureCountDTO(String date, long count) {
}
