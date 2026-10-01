package com.careconnect.dto.evv;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.*;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Map;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvvCorrectionRequestDto {

    @NotNull
    private Long originalRecordId;

    @NotBlank
    @Size(max = 50)
    private String reasonCode;

    @NotBlank
    @Size(max = 1000)
    private String explanation;

    // Updated field values
    private String serviceType;
    private String individualName;
    private LocalDate dateOfService;
    private OffsetDateTime timeIn;
    private OffsetDateTime timeOut;
    private Double locationLat;
    private Double locationLng;
    private String locationSource;
    private String stateCode;
    private Map<String, Object> deviceInfo;

    // Check-in/check-out location fields for saving to evv_record_location table
    private Double checkinLocationLat;
    private Double checkinLocationLng;
    private String checkinLocationSource;
    private Double checkoutLocationLat;
    private Double checkoutLocationLng;
    private String checkoutLocationSource;
}

