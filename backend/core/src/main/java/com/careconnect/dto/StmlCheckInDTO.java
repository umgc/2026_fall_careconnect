package com.careconnect.dto;

import java.time.LocalDateTime;
import java.util.List;
import lombok.Builder;
import lombok.Data;

/**
 * DTO for STML-3 caregiver check-in preparation view.
 */
@Data
@Builder
public class StmlCheckInDTO {

    private Long patientId;
    private Long caregiverId;
    private LocalDateTime generatedAt;
    private List<StmlCheckInItemDTO> notes;
    private List<StmlCheckInItemDTO> pendingItems;
    private String disclaimer;
    private boolean consentGranted;

    /**
     * Represents a single note or pending item in the check-in view.
     */
    @Data
    @Builder
    public static class StmlCheckInItemDTO {
        private String type;
        private String summary;
        private String date;
        private String source;
    }
}