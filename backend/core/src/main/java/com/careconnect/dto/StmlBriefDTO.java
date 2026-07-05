package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;
import java.time.LocalDateTime;
import java.util.List;

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