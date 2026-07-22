package com.careconnect.dto;

import java.util.List;

/** Aggregated anonymous HTTP error telemetry. */
public record ErrorMetricsDTO(long totalErrors, List<EndpointErrorCountDTO> byEndpointBucket) {}
