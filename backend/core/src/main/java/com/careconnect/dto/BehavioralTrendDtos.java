package com.careconnect.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * DTOs for GET /clients/{id}/reports/behavioral-trends.
 */
public class BehavioralTrendDtos {

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class WeekCount {
        private String weekStartDate;
        private int incidentCount;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class BehavioralTrendsResponse {
        /**
         * "UP", "STABLE", or "DOWN" for trend indicator
         */
        private String trend;
        private List<WeekCount> weeklyCounts;
        /**
         * Top 3 most frequently observed behavior keywords
         */
        private List<String> topKeywords;
    }
}
