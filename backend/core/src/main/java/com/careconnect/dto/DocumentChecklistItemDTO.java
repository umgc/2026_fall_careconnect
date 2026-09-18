package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * One required document type on a subject's compliance checklist, with its
 * current status and the evidence (uploaded files / digitized record) behind it.
 */
@Data
@Builder
public class DocumentChecklistItemDTO {
    private String documentType;
    /**
     * MISSING | IN_PROGRESS | COMPLETE | REJECTED
     */
    private String status;
    /**
     * True when the status comes from a recorded transition rather than derivation.
     */
    private boolean tracked;
    /**
     * Number of active uploaded files of this type linked to the subject.
     */
    private int fileCount;
    /**
     * True when a digitized structured record exists for this document type.
     */
    private boolean hasStructuredEntry;
    /**
     * Most recent uploaded file of this type, if any.
     */
    private Long latestFileId;
    private String latestFilename;
    private LocalDateTime latestUploadAt;
    /**
     * Reason recorded with the latest transition, if tracked.
     */
    private String notes;
    private Long updatedBy;
    private LocalDateTime updatedAt;
}
