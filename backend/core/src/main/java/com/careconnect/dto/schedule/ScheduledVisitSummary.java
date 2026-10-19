package com.careconnect.dto.schedule;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ScheduledVisitSummary {

    private long overdue;
    private long ready;
    private long upcoming;
    private long totalToday;
}
