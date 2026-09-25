package com.careconnect.model;

import java.time.LocalDateTime;

import com.fasterxml.jackson.annotation.JsonBackReference;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity class representing a scheduled notification in the system.
 *
 * <p>
 * Each {@code ScheduledNotification} corresponds to a record in the
 * {@code scheduled_notification} database table. It stores metadata about
 * when a notification should be delivered, its content, type, status,
 * and delivery tracking details.
 * </p>
 *
 * <p>
 * Relationships:
 * <ul>
 * <li>Many-to-one association with {@link Task}, meaning each notification
 * is linked to a specific task.</li>
 * </ul>
 * </p>
 *
 * <p>
 * Lifecycle:
 * <ul>
 * <li>{@code createdAt} is set when the entity is instantiated.</li>
 * <li>{@code updatedAt} is automatically refreshed on every update
 * using the {@link #setLastUpdate()} method.</li>
 * </ul>
 * </p>
 */
@Entity
@Table(name = "scheduled_notification")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ScheduledNotification {

    /**
     * Primary key (auto-generated).
     */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * The ID of the user who should receive this notification.
     * <p>
     * <b>Required.</b>
     * </p>
     */
    @Column(nullable = false)
    private Long receiverId;

    /**
     * Short title of the notification.
     * <p>
     * Maximum length: 255 characters. <b>Required.</b>
     * </p>
     */
    @Column(nullable = false, length = 255)
    private String title;

    /**
     * Body text of the notification (detailed message).
     * <p>
     * Stored as {@code TEXT} in the database to allow larger content.
     * </p>
     * <p>
     * <b>Required.</b>
     * </p>
     */
    @Column(nullable = false, columnDefinition = "TEXT")
    private String body;

    /**
     * Type of notification.
     * <p>
     * Examples: {@code REMINDER}, {@code ALERT}, {@code EMERGENCY}.
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    private String notificationType;

    /**
     * Date and time when the notification is scheduled to be sent.
     * <p>
     * <b>Required.</b>
     * </p>
     */
    @Column(nullable = false)
    private LocalDateTime scheduledTime;

    /**
     * The date and time when the notification was actually sent.
     * <p>
     * Remains null until delivery occurs.
     * </p>
     */
    private LocalDateTime sentTime;

    /**
     * Current status of the notification.
     *
     * <p>
     * Possible values:
     * <ul>
     * <li>{@code PENDING} – waiting to be sent</li>
     * <li>{@code SENT} – successfully delivered</li>
     * <li>{@code FAILED} – delivery attempt failed</li>
     * <li>{@code CANCELLED} – cancelled before sending</li>
     * </ul>
     * </p>
     *
     * <p>
     * Defaults to {@code PENDING}.
     * </p>
     */
    @Builder.Default
    @Column(nullable = false)
    private String status = "PENDING";

    /**
     * External message ID returned by the notification service provider
     * (e.g., FCM/APNs ID). Useful for tracking delivery.
     */
    private String messageId;

    /**
     * Error details in case sending fails.
     */
    private String errorMessage;

    /**
     * Timestamp when the notification record was created.
     * <p>
     * Immutable after creation.
     * </p>
     */
    @Builder.Default
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    /**
     * Timestamp of the last update.
     * <p>
     * Automatically refreshed on every update via {@link #setLastUpdate()}.
     * </p>
     */
    @Builder.Default
    @Column(nullable = false)
    private LocalDateTime updatedAt = LocalDateTime.now();
    /**
     * Task that this notification is associated with.
     *
     * <p>
     * Each task may have multiple notifications scheduled.
     * </p>
     *
     * <p>
     * Relationship:
     * <ul>
     * <li>{@code ManyToOne}: multiple notifications per task</li>
     * <li>{@code FetchType.LAZY}: task is loaded only when accessed</li>
     * <li>{@code @JsonBackReference}: prevents circular references in JSON
     * serialization (paired with {@code @JsonManagedReference} on Task).</li>
     * </ul>
     * </p>
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "task_id", nullable = false)
    @JsonBackReference
    private Task task;

    /**
     * Callback executed before each entity update.
     * <p>
     * Updates the {@code updatedAt} field to the current timestamp.
     * </p>
     */
    @PreUpdate
    public void setLastUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}
