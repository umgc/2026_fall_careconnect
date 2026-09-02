package com.careconnect.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MoodPainAnalyticsDTO {

    private LocalDateTime periodStart;
    private LocalDateTime periodEnd;

    // Summary statistics
    private Double avgMood;
    private Double avgPain;
    private Integer totalEntries;
    private Integer moodEntries;
    private Integer painEntries;

    // Trend data
    private Double moodTrend;        // positive = improving, negative = declining
    private Double painTrend;        // positive = increasing pain, negative = decreasing pain

    // Range data
    private Integer minMood;
    private Integer maxMood;
    private Integer minPain;
    private Integer maxPain;

    // Time series data for charts
    private List<MoodPainTimeSeriesPoint> timeSeries;

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class MoodPainTimeSeriesPoint {
        private LocalDateTime timestamp;
        private Integer moodValue;
        private Integer painValue;
        private String note;
    }
}
