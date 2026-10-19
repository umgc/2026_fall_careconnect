package com.careconnect.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class Metrics {
    private Long id;
    private String metricType;
    private Double value;
    private String unit;
    private LocalDateTime timestamp;
    private Long patientId;
    private String source; // "fitbit", "manual", etc.

    // Explicit setters to ensure compilation works if Lombok isn't processing
    public void setMetricType(String metricType) {
        this.metricType = metricType;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public void setTimestamp(LocalDateTime timestamp) {
        this.timestamp = timestamp;
    }
}
