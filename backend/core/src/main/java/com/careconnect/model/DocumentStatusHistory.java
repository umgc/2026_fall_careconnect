package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

/**
 * Immutable audit record of a document compliance status transition: which
 * subject and document type changed, from what status to what status, who made
 * the change, when it occurred and why. Records can never be updated or
 * deleted (matches the ActivityLog immutability pattern).
 */
@Entity
@Table(name = "document_status_history")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DocumentStatusHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "subject_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private DocumentRequirementStatus.SubjectType subjectType;

    @Column(name = "subject_id", nullable = false)
    private Long subjectId;

    @Column(name = "document_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private UserFile.FileCategory documentType;

    /** Null on the very first transition for a requirement. */
    @Column(name = "previous_status")
    @Enumerated(EnumType.STRING)
    private DocumentRequirementStatus.ComplianceStatus previousStatus;

    @Column(name = "new_status", nullable = false)
    @Enumerated(EnumType.STRING)
    private DocumentRequirementStatus.ComplianceStatus newStatus;

    /** users.id of the person (or acting uploader) who made the change. */
    @Column(name = "changed_by", nullable = false)
    private Long changedBy;

    @Column(name = "reason", nullable = false, length = 1024)
    private String reason;

    @Column(name = "changed_at", nullable = false)
    private LocalDateTime changedAt;

    @PrePersist
    protected void onCreate() {
        if (changedAt == null) {
            changedAt = LocalDateTime.now();
        }
    }

    // Prevent updates/deletes (immutable audit trail)
    @PreUpdate
    @PreRemove
    private void preventUpdateOrDelete() {
        throw new UnsupportedOperationException(
                "DocumentStatusHistory records are immutable; updates and deletes are not allowed.");
    }

    // Manual getters for Lombok compatibility (matches UserFile style)
    public Long getId() { return id; }
    public DocumentRequirementStatus.SubjectType getSubjectType() { return subjectType; }
    public Long getSubjectId() { return subjectId; }
    public UserFile.FileCategory getDocumentType() { return documentType; }
    public DocumentRequirementStatus.ComplianceStatus getPreviousStatus() { return previousStatus; }
    public DocumentRequirementStatus.ComplianceStatus getNewStatus() { return newStatus; }
    public Long getChangedBy() { return changedBy; }
    public String getReason() { return reason; }
    public LocalDateTime getChangedAt() { return changedAt; }
}
