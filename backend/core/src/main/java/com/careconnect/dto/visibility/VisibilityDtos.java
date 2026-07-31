package com.careconnect.dto.visibility;

import jakarta.validation.constraints.NotNull;
import lombok.*;

import java.time.LocalDateTime;

public class VisibilityDtos {

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class VisibilityRequest {
        @NotNull private Long caregiverUserId;
        @NotNull private Long patientUserId;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class VisibilityResponse {
        private Long id;
        private Long caregiverUserId;
        private Long patientUserId;
        private String status;
        private boolean canViewSummaries;
        private Long requestedBy;
        private Long reviewedBy;
        private LocalDateTime reviewedAt;
        private LocalDateTime updatedAt;
    }
}
