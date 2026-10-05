package com.careconnect.dto.evv;

import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.model.evv.NoGpsReason;
import jakarta.validation.constraints.*;
import lombok.*;

import java.math.BigDecimal;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvvLocationRequest {

    @NotNull(message = "EVV record ID is required")
    private Long evvRecordId;

    @NotNull(message = "Location role is required")
    private EvvLocationRole role;

    @NotNull(message = "Location type is required")
    private EvvLocationType type;

    private CoordinatesDto coords;

    /**
     * Required when type is PATIENT_ADDRESS or MANUAL (federal EVV compliance)
     */
    private NoGpsReason noGpsReason;

    /**
     * Free-form address; required when type is MANUAL
     */
    @Size(max = 500)
    private String manualAddress;

    /**
     * Validate the request based on location type.
     * Federal EVV regulations require noGpsReason whenever GPS is not used.
     */
    public void validate() {
        if (type == EvvLocationType.GPS) {
            if (coords == null || coords.getLat() == null || coords.getLng() == null) {
                throw new IllegalArgumentException("GPS location requires coordinates");
            }
        } else if (type == EvvLocationType.PATIENT_ADDRESS) {
            // PATIENT_ADDRESS doesn't need coords - address will be fetched from patient
            if (noGpsReason == null) {
                throw new IllegalArgumentException(
                        "A noGpsReason is required when using PATIENT_ADDRESS (federal EVV requirement)");
            }
        } else if (type == EvvLocationType.MANUAL) {
            if (manualAddress == null || manualAddress.isBlank()) {
                throw new IllegalArgumentException("MANUAL location type requires a manualAddress");
            }
            if (noGpsReason == null) {
                throw new IllegalArgumentException(
                        "A noGpsReason is required when using MANUAL location (federal EVV requirement)");
            }
        }
    }

    /**
     * Nested DTO for GPS coordinates
     */
    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class CoordinatesDto {

        @NotNull(message = "Latitude is required for GPS location")
        @DecimalMin(value = "-90.0", message = "Latitude must be between -90 and 90")
        @DecimalMax(value = "90.0", message = "Latitude must be between -90 and 90")
        private BigDecimal lat;

        @NotNull(message = "Longitude is required for GPS location")
        @DecimalMin(value = "-180.0", message = "Longitude must be between -180 and 180")
        @DecimalMax(value = "180.0", message = "Longitude must be between -180 and 180")
        private BigDecimal lng;

        @DecimalMin(value = "0.0", message = "Accuracy must be positive")
        private BigDecimal accuracyM;
    }
}

