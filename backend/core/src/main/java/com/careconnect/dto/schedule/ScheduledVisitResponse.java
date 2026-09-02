package com.careconnect.dto.schedule;

import com.careconnect.model.schedule.ScheduledVisit;
import lombok.AllArgsConstructor;
import lombok.Data;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.LocalDateTime;

@AllArgsConstructor
@Data
public class ScheduledVisitResponse {

    private Long id;
    private Long caregiverId;
    private Long patientId;
    private String patientName;
    private String serviceType;
    private LocalDate scheduledDate;
    private LocalTime scheduledTime;
    private Integer durationMinutes;
    private String priority;
    private String notes;
    private String status;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public ScheduledVisitResponse() {
    }

    public ScheduledVisitResponse(ScheduledVisit visit, String patientName) {
        this.id = visit.getId();
        this.caregiverId = visit.getCaregiverId();
        this.patientId = visit.getPatientId();
        this.patientName = patientName;
        this.serviceType = visit.getServiceType();
        this.scheduledDate = visit.getScheduledDate();
        this.scheduledTime = visit.getScheduledTime();
        this.durationMinutes = visit.getDurationMinutes();
        this.priority = visit.getPriority();
        this.notes = visit.getNotes();
        this.status = visit.getStatus();
        this.createdAt = visit.getCreatedAt();
        this.updatedAt = visit.getUpdatedAt();
    }
}
