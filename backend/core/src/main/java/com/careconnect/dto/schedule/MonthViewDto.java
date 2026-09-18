package com.careconnect.dto.schedule;

import lombok.Data;

import java.time.LocalDate;
import java.util.Map;

@Data
public class MonthViewDto {
    private Integer month;
    private Integer year;
    private Map<LocalDate, CalendarViewDto> days;
}
