package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

import java.util.List;

/** A subject's full required-document checklist with per-status counts. */
@Data
@Builder
public class DocumentChecklistDTO {
    /** EMPLOYEE | CARE_CIRCLE */
    private String subjectType;
    private Long subjectId;
    private String subjectName;
    private List<DocumentChecklistItemDTO> items;
    private int requiredCount;
    private int missingCount;
    private int inProgressCount;
    private int completeCount;
    private int rejectedCount;
    /** 0-100, share of required documents in COMPLETE state. */
    private int percentComplete;
}
