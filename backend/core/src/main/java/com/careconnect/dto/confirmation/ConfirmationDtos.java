package com.careconnect.dto.confirmation;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.*;

import java.time.LocalDateTime;

public class ConfirmationDtos {

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class ConfirmationItemResponse {
        private Long id;
        private String sourceType;
        private String status;
        private String payload;
        private String referenceId;
        private Long requestedBy;
        private Long resolvedBy;
        private LocalDateTime resolvedAt;
        private String resolutionNote;
        private LocalDateTime createdAt;
        private LocalDateTime updatedAt;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class CreateConfirmationRequest {
        @NotNull private String sourceType;
        @NotNull private String payload;
        private String referenceId;
        @NotNull private Long requestedBy;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class ResolveConfirmationRequest {
        @Size(max = 500)
        private String note;
    }
}
