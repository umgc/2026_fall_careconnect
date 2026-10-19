package com.careconnect.dto.evv;

import lombok.*;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Map;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvvRecordResponse {
    private Long id;

    // Patient linkage
    private Long patientId;
    private String patientMaNumber;

    // Core fields
    private String serviceType;
    private String individualName;
    private Long caregiverId;
    private LocalDate dateOfService;
    private OffsetDateTime timeIn;
    private OffsetDateTime timeOut;

    // Location
    private Double locationLat;
    private Double locationLng;
    private String locationSource; // gps|manual

    // State & status
    private String stateCode; // MD|DC|VA
    private String status;    // DRAFT|PENDING_REVIEW|CONFIRMED|SUBMITTED|FAILED_SUBMISSION

    // Metadata
    private Map<String, Object> deviceInfo;
    private OffsetDateTime createdAt;
    private OffsetDateTime updatedAt;
}