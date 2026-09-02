package com.careconnect.dto.evv;

import jakarta.validation.constraints.*;
import lombok.*;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Map;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvvRecordRequestDto {
    @NotBlank
    @Size(max = 128)
    private String serviceType;

    @NotBlank
    @Size(max = 200)
    private String individualName;

    @NotNull
    @Positive
    private Long caregiverId;

    @NotNull
    private LocalDate dateOfService;

    @NotNull
    private OffsetDateTime timeIn;

    @NotNull
    private OffsetDateTime timeOut;

    // Legacy location fields (kept for backward compatibility)
    // Note: New implementations should use the EVV Location API endpoints instead
    @DecimalMin(value = "-90.0", inclusive = true)
    @DecimalMax(value = "90.0", inclusive = true)
    private Double locationLat;

    @DecimalMin(value = "-180.0", inclusive = true)
    @DecimalMax(value = "180.0", inclusive = true)
    private Double locationLng;

    @Pattern(regexp = "gps|manual|GPS|PATIENT_ADDRESS")
    private String locationSource;

    // Check-in/check-out location fields for convenience
    // These will be saved to evv_record_location table via EvvLocationService
    private Double checkinLocationLat;
    private Double checkinLocationLng;
    @Pattern(regexp = "GPS|PATIENT_ADDRESS|MANUAL")
    private String checkinLocationSource;
    /**
     * Federal EVV: reason GPS was unavailable for check-in (required when not GPS)
     */
    private String checkinNoGpsReason;
    /**
     * Manual address for check-in MANUAL location type
     */
    private String checkinManualAddress;
    /**
     * GPS accuracy in metres for check-in
     */
    private Double checkinAccuracyM;

    private Double checkoutLocationLat;
    private Double checkoutLocationLng;
    @Pattern(regexp = "GPS|PATIENT_ADDRESS|MANUAL")
    private String checkoutLocationSource;
    /**
     * Federal EVV: reason GPS was unavailable for check-out (required when not GPS)
     */
    private String checkoutNoGpsReason;
    /**
     * Manual address for check-out MANUAL location type
     */
    private String checkoutManualAddress;
    /**
     * GPS accuracy in metres for check-out
     */
    private Double checkoutAccuracyM;

    @NotNull
    @Positive
    private Long patientId; // Direct reference to patient receiving care

    @NotBlank
    @Pattern(regexp = "MD|DC|VA")
    private String stateCode;

    private Map<String, Object> deviceInfo;

    // Optional link to scheduled visit (if this EVV record fulfills a scheduled visit)
    private Long scheduledVisitId;
}
