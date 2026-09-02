package com.careconnect.dto.schedule;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ConflictCheckResponse {
    private boolean hasConflicts;
    private List<String> conflictMessages;
    private List<String> warnings;
    private List<ScheduledVisitResponse> conflictingVisits;
    private boolean exceedsDailyLimit;
    private boolean exceedsDailyHours;
}