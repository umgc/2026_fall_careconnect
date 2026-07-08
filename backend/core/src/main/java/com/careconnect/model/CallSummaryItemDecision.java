package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreRemove;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * Append-only audit record of per-item confirmation, session-approval, or
 * dismissal decisions on a stored {@link CallSummary}. Required by FR-SUM-4
 * (user confirmation gate) and the team TDD section 6.2.2 contract that every
 * confirmation creates an immutable audit record.
 *
 * <p>Backing table {@code call_summary_item_decisions} is protected by the
 * {@code reject_update_delete_immutable} trigger installed in migration V44;
 * the JPA lifecycle guard below provides the same protection on the Java side
 * so violations surface earlier with a clearer message.
 */
@Entity
@Table(name = "call_summary_item_decisions")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CallSummaryItemDecision {

    /** Database identifier for the decision row. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Foreign key to {@link CallSummary#getId()}. */
    @Column(name = "summary_id", nullable = false)
    private Long summaryId;

    /**
     * Identifier of the extracted item inside the summary payload (for example,
     * the UUID of an {@code action_item}, {@code appointment}, or
     * {@code care_instruction}).
     */
    @Column(name = "item_id", nullable = false, length = 120)
    private String itemId;

    /**
     * Item category, matching the field in the summary payload that contains
     * the item (for example {@code action_item}, {@code appointment},
     * {@code care_instruction}).
     */
    @Column(name = "item_type", nullable = false, length = 32)
    private String itemType;

    /**
     * Decision recorded by the acting user. Permitted values match the team
     * TDD section 6.2.2 contract: {@code approve}, {@code approve-for-session},
     * or {@code decline}.
     */
    @Column(name = "decision", nullable = false, length = 24)
    private String decision;

    /**
     * Destination for an approved item write (for example {@code calendar},
     * {@code reminders}, or {@code care_plan}). Null for {@code decline}
     * decisions and for approvals that do not require a downstream write.
     */
    @Column(name = "destination", length = 32)
    private String destination;

    /**
     * Identifier of the user who made the decision. Nullable to preserve the
     * audit row if the user is later deleted (foreign key uses ON DELETE SET
     * NULL).
     */
    @Column(name = "decided_by_user_id")
    private Long decidedByUserId;

    /** Timestamp when the decision was recorded. */
    @Column(name = "decided_at", nullable = false)
    private LocalDateTime decidedAt;

    /** Optional free-text notes captured with the decision. */
    @Column(name = "notes", columnDefinition = "TEXT")
    private String notes;

    /** Timestamp when the audit row was persisted. */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** Populates audit timestamps when not explicitly set by the caller. */
    @PrePersist
    public void onCreate() {
        final LocalDateTime now = LocalDateTime.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (decidedAt == null) {
            decidedAt = now;
        }
    }

    /**
     * Belt-and-suspenders guard against accidental updates or deletes from
     * application code. The database trigger
     * {@code tr_call_summary_item_decisions_immutable} enforces the same rule
     * at the storage layer; this guard surfaces the violation earlier with a
     * clearer message.
     */
    @PreUpdate
    @PreRemove
    private void preventUpdateOrDelete() {
        throw new UnsupportedOperationException(
                "CallSummaryItemDecision records are immutable; updates and "
                        + "deletes are not allowed.");
    }
}
