package com.careconnect.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * DTOs for GET /clients/{id}/reports/competency-trends.
 */
public class CompetencyTrendDtos {

    /**
     * One data point: week start date, average score, and log count for that activity that week.
     */
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class WeekDataPoint {
        private String weekStartDate; // ISO date e.g. "2025-01-06"
        private double averageCompetencyScore;
        private int logCount;
    }

    /**
     * One activity's trend: list of weekly data points.
     */
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ActivityTrend {
        private Long activityId;
        private String activityName;
        private List<WeekDataPoint> dataPoints;
    }

    /**
     * Full response: overall status and per-activity trends.
     */
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class CompetencyTrendsResponse {
        /**
         * "IMPROVING", "STABLE", or "DECLINING"
         */
        private String status;
        private List<String> weekLabels; // sorted week start dates
        private List<ActivityTrend> activityTrends;
    }
}
