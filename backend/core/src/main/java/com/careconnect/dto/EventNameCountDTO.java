package com.careconnect.dto;

/** Count of telemetry events grouped by event name. */
public record EventNameCountDTO(String eventName, long count) {}
