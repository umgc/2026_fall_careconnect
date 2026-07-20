package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * Structured form entry captured from an uploaded document, including a link
 * back to the original file kept as supporting evidence.
 */
@Data
@Builder
public class StructuredDocumentEntryDTO {
    private Long id;
    private Long fileId;
    private String documentType;
    private Long patientId;
    private Long employeeUserId;
    private Map<String, String> fields;
    private Long createdBy;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // Linked original file (supporting evidence)
    private String originalFilename;
    private String fileUrl;
}
