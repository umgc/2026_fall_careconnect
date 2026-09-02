package com.careconnect.model.schedule;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedDate;

import jakarta.persistence.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "scheduled_visit_audits")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ScheduledVisitAudit {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "visit_id", nullable = false)
    private Long visitId;

    @Column(name = "action", nullable = false, length = 50)
    private String action; // CREATED, UPDATED, DELETED

    @Column(name = "changed_field", length = 100)
    private String changedField; // Field name that changed

    @Column(name = "old_value", columnDefinition = "TEXT")
    private String oldValue;

    @Column(name = "new_value", columnDefinition = "TEXT")
    private String newValue;

    @CreatedDate
    @Column(name = "changed_at", nullable = false)
    private LocalDateTime changedAt;

    @Column(name = "changed_by", length = 100)
    private String changedBy;
}