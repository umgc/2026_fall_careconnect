package com.careconnect.dto;

import lombok.Data;

/**
 * Request body for manually transitioning a required document's compliance status.
 */
@Data
public class DocumentStatusUpdateRequest {
    /**
     * EMPLOYEE | CARE_CIRCLE
     */
    private String subjectType;
    private Long subjectId;
    private String documentType;
    /**
     * Target status: MISSING | IN_PROGRESS | COMPLETE | REJECTED
     */
    private String status;
    /**
     * Why the change is being made; required for the audit trail.
     */
    private String reason;
}
