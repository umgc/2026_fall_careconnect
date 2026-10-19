package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * One audit-trail entry: who changed a document's status, when and why.
 */
@Data
@Builder
public class DocumentStatusHistoryDTO {
    private Long id;
    private String subjectType;
    private Long subjectId;
    private String documentType;
    private String previousStatus;
    private String newStatus;
    private Long changedBy;
    private String changedByName;
    private String reason;
    private LocalDateTime changedAt;
}
