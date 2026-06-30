package com.careconnect.model.confirmation;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Getter @Setter @Builder @NoArgsConstructor @AllArgsConstructor
@Entity @Table(name = "confirmation_items")
public class ConfirmationItem {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(name = "source_type", nullable = false, length = 32)
    private ConfirmationSourceType sourceType;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    @Builder.Default
    private ConfirmationStatus status = ConfirmationStatus.PENDING;

    @Column(name = "payload", nullable = false, columnDefinition = "TEXT")
    private String payload;

    @Column(name = "reference_id", length = 120)
    private String referenceId;

    @Column(name = "requested_by", nullable = false)
    private Long requestedBy;

    @Column(name = "resolved_by")
    private Long resolvedBy;

    @Column(name = "resolved_at")
    private LocalDateTime resolvedAt;

    @Column(name = "resolution_note", length = 500)
    private String resolutionNote;

    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    public void confirm(Long resolverUserId, String note) {
        this.status = ConfirmationStatus.CONFIRMED;
        this.resolvedBy = resolverUserId;
        this.resolvedAt = LocalDateTime.now();
        this.resolutionNote = note;
        this.updatedAt = LocalDateTime.now();
    }

    public void dismiss(Long resolverUserId, String note) {
        this.status = ConfirmationStatus.DISMISSED;
        this.resolvedBy = resolverUserId;
        this.resolvedAt = LocalDateTime.now();
        this.resolutionNote = note;
        this.updatedAt = LocalDateTime.now();
    }

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
