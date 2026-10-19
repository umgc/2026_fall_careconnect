package com.careconnect.dto;

import lombok.Builder;

@Builder
public record MedicalSummaryDTO(
        // Counts for quick overview
        int totalAllergies,
        int activeMedications,
        int totalVitalReadings,
        int totalMoodPainEntries,

        // Recent activity indicators
        boolean hasRecentVitals, // within last 7 days
        boolean hasRecentMoodPain, // within last 7 days

        // Health status indicators
        String overallHealthStatus, // "Good", "Needs Attention", "Critical"
        String lastActivityDate // Last time any health data was recorded
) {
}
