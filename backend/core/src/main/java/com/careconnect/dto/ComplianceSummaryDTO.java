package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

/** One dashboard row: a subject's aggregate document compliance position. */
@Data
@Builder
public class ComplianceSummaryDTO {
    /** EMPLOYEE | CARE_CIRCLE */
    private String subjectType;
    private Long subjectId;
    private String subjectName;
    private int requiredCount;
    private int missingCount;
    private int inProgressCount;
    private int completeCount;
    private int rejectedCount;
    private int percentComplete;
    /** True when any required document is missing or rejected (onboarding blocker). */
    private boolean blocked;
}
