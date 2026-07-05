package com.careconnect.dto;

import java.time.LocalDateTime;
import java.util.List;
import lombok.Builder;
import lombok.Data;

/**
 * DTO for STML-2 daily memory brief response.
 */
@Data
@Builder
public class StmlBriefDTO {
    private Long patientId;
    private LocalDateTime generatedAt;
    private List<StmlCardDTO> cards;
    private String disclaimer;

    @Data
    @Builder
    public static class StmlCardDTO {
        private String type;        // "RECALL", "APPOINTMENT", "ACTION_ITEM", "MEDICATION"
        private String headline;
        private String detail;
        private String sourceType; // what data this came from
        private LocalDateTime timestamp;
    }
}