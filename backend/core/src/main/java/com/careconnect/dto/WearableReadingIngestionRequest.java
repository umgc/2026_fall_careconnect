package com.careconnect.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;

public record WearableReadingIngestionRequest(
        Long patientId,
        String source,
        @NotEmpty(message = "readings must not be empty")
        @Size(max = 500, message = "readings must not exceed 500 entries")
        List<@Valid WearableReadingPayload> readings
) {
    public record WearableReadingPayload(
            @NotNull(message = "metric is required")
            String metric,
            @NotNull(message = "metricValue is required")
            Double metricValue,
            @NotNull(message = "recordedAt is required")
            Instant recordedAt,
            String source
    ) {
    }
}
