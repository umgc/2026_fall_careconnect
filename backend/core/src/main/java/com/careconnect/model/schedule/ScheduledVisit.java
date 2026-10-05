package com.careconnect.model.schedule;

import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedBy;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedBy;
import org.springframework.data.annotation.LastModifiedDate;

import jakarta.persistence.*;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.LocalDateTime;

@Entity
@Table(name = "scheduled_visits")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class ScheduledVisit {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "caregiver_id", nullable = false)
    private Long caregiverId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "service_type", nullable = false, length = 100)
    private String serviceType;

    @Column(name = "scheduled_date", nullable = false)
    private LocalDate scheduledDate;

    @Column(name = "scheduled_time", nullable = false)
    private LocalTime scheduledTime;

    @Column(name = "duration_minutes", nullable = false)
    private Integer durationMinutes = 60;

    @Column(name = "priority", nullable = false, length = 20)
    private String priority = "Normal";

    @Column(name = "notes", columnDefinition = "TEXT")
    private String notes;

    @Column(name = "status", nullable = false, length = 50)
    private String status = "Scheduled";

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @Column(name = "conflict_flag")
    private Boolean conflictFlag = false;

    @Column(name = "conflict_warning", columnDefinition = "TEXT")
    private String conflictWarning;

    @CreatedBy
    @Column(name = "created_by", length = 100)
    private String createdBy;

    @LastModifiedBy
    @Column(name = "updated_by", length = 100)
    private String updatedBy;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
        if (updatedAt == null) {
            updatedAt = LocalDateTime.now();
        }
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    public void markInProgress() {
        this.status = "In Progress";
    }

    public void markCompleted() {
        this.status = "Completed";
    }

    public void markCancelled() {
        this.status = "Cancelled";
    }

    public void markNoShow() {
        this.status = "No Show";
    }

    public boolean isScheduled() {
        return "Scheduled".equals(this.status);
    }

    public boolean isCompleted() {
        return "Completed".equals(this.status);
    }

    public boolean isCancelled() {
        return "Cancelled".equals(this.status);
    }

    // Explicit getters added due to Lombok processing issue
    public Long getId() {
        return id;
    }

    public Long getCaregiverId() {
        return caregiverId;
    }

    public Long getPatientId() {
        return patientId;
    }

    public String getServiceType() {
        return serviceType;
    }

    public java.time.LocalDate getScheduledDate() {
        return scheduledDate;
    }

    public java.time.LocalTime getScheduledTime() {
        return scheduledTime;
    }

    public Integer getDurationMinutes() {
        return durationMinutes;
    }

    public String getPriority() {
        return priority;
    }

    public String getNotes() {
        return notes;
    }

    public String getStatus() {
        return status;
    }

    public java.time.LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public java.time.LocalDateTime getUpdatedAt() {
        return updatedAt;
    }
}
