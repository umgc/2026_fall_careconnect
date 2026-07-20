package com.careconnect.dto;

import com.careconnect.model.WearableMetric;
import lombok.Builder;

import java.time.Instant;
import java.util.List;

@Builder
public record WearableReadingIngestionResponse(
        Long patientId,
        String source,
        int acceptedCount,
        int rejectedCount,
        List<IngestedReading> acceptedReadings,
        List<RejectedReading> rejectedReadings
) {
    public record IngestedReading(
            WearableMetric.MetricType metric,
            Double metricValue,
            Instant recordedAt,
            String source
    ) {}

    public record RejectedReading(
            int index,
            String metric,
            Double metricValue,
            Instant recordedAt,
            String source,
            String error
    ) {}
}
