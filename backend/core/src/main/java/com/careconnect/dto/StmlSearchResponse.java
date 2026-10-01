package com.careconnect.dto;

import java.time.LocalDateTime;
import java.util.List;

import lombok.Builder;
import lombok.Data;

/**
 * Response DTO for STML-4 recall history search.
 */
@Data
@Builder
public class StmlSearchResponse {
    private Long patientId;
    private String keyword;
    private int totalResults;
    private List<StmlSearchResultDTO> results;
    private LocalDateTime searchedAt;

    /**
     * Represents a single search result item.
     */
    @Data
    @Builder
    public static class StmlSearchResultDTO {
        private String sourceType;
        private String content;
        private String sender;
        private String date;
        private String conversationId;
    }
}