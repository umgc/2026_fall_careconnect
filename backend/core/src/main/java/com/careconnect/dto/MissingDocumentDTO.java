package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * One outstanding required form (MISSING or REJECTED) for the filterable report / export.
 */
@Data
@Builder
public class MissingDocumentDTO {
    /**
     * EMPLOYEE | CARE_CIRCLE
     */
    private String subjectType;
    private Long subjectId;
    private String subjectName;
    private String documentType;
    /**
     * MISSING | REJECTED
     */
    private String status;
    /**
     * Reason recorded with the latest transition (e.g. why it was rejected).
     */
    private String notes;
    private LocalDateTime updatedAt;
}
