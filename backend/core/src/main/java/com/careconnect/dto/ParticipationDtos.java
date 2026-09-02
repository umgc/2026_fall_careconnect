package com.careconnect.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

/**
 * DTOs for GET /clients/{id}/reports/participation.
 */
public class ParticipationDtos {

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class WeekCount {
        private String weekStartDate;
        private int totalLogs;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ActivityParticipation {
        private Long activityId;
        private String activityName;
        private String category; // ADL or IADL
        private int totalLogsInPeriod;
        private LocalDateTime lastLoggedAt;
        private boolean noRecentActivity; // true if no logs in past 7 days
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ParticipationResponse {
        /**
         * "IMPROVING", "STABLE", or "DECLINING" based on last 2 weeks vs prior 2 weeks.
         */
        private String status;
        private List<WeekCount> weeklyCounts;
        private List<ActivityParticipation> activities;
    }
}
