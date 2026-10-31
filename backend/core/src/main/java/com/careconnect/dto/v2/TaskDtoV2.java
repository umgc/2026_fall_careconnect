package com.careconnect.dto.v2;

import java.time.LocalDateTime;
import java.util.List;

import com.careconnect.dto.ScheduledNotificationDTO;

import io.micrometer.common.lang.Nullable;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Data Transfer Object (DTO) for representing tasks in API v2.
 *
 * <p>
 * This DTO defines the structure of task-related data exchanged
 * between the client and server. It ensures that only relevant fields
 * are exposed to API consumers, separate from the {@code Task} entity.
 * </p>
 *
 * <p>
 * Key features:
 * <ul>
 * <li>Includes recurrence fields such as {@code frequency}, {@code interval},
 * and {@code daysOfWeek} for supporting recurring tasks.</li>
 * <li>Allows flattening of patient relationship into just {@code patientId}
 * instead of exposing the full patient entity.</li>
 * <li>Supports optional {@code notifications} for linking scheduled
 * reminders.</li>
 * <li>Supports {@code updateSeries} flag for bulk updates to recurring
 * tasks.</li>
 * </ul>
 * </p>
 */
@Data
@AllArgsConstructor
@Builder
@NoArgsConstructor
public class TaskDtoV2 {
    /**
     * Unique identifier of the task.
     */
    private Long id;

    /**
     * Name of the task.
     * <p>
     * <b>Required.</b>
     * </p>
     */
    @NotNull(message = "Task name is required")
    private String name;

    /**
     * Optional description providing more details about the task.
     */
    @Nullable
    private String description;

    /**
     * Date of the task.
     * <p>
     * Stored as {@code varchar(255)} in the database. Should be in
     * a consistent format (e.g., ISO-8601) for parsing.
     * </p>
     * <p>
     * <b>Required.</b>
     * </p>
     */
    @NotNull(message = "Date is required")
    private String date; // Stored as varchar(255) in DB

    /**
     * Optional time of day for the task.
     * <p>
     * Stored as {@code varchar(255)} in the database
     * (e.g., "08:30 AM").
     * </p>
     */
    @Nullable
    private String timeOfDay; // Stored as varchar(255) in DB

    /**
     * Completion state of the task.
     * <p>
     * <b>Required.</b>
     * </p>
     */
    @NotNull(message = "Completion state is required")
    private boolean isCompleted;

    /**
     * Frequency of recurrence.
     * <p>
     * Examples: {@code "daily"}, {@code "weekly"}, {@code "monthly"}.
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private String frequency;

    /**
     * Interval for the recurrence.
     * <p>
     * Examples:
     * <ul>
     * <li>1 → every day/week</li>
     * <li>2 → every 2 days/weeks</li>
     * </ul>
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private Integer interval;

    /**
     * Number of occurrences for this task.
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private Integer count;

    /**
     * Days of the week this task applies to.
     *
     * <p>
     * Typically represented as a list of 7 booleans, one for each day
     * (e.g., {@code [true, false, true, false, false, true, false]}
     * for Mon/Wed/Sat).
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private List<Boolean> daysOfWeek;

    /**
     * Type of task.
     * <p>
     * Examples: {@code "Medication"}, {@code "Appointment"},
     * {@code "Exercise"}, {@code "Lab"}, {@code "Pharmacy"},
     * {@code "General"}.
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private String taskType;

    /**
     * Flattened patient reference.
     *
     * <p>
     * Used in update flows to reassign a task to a patient
     * without needing the full {@code Patient} object.
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private Long patientId;

    /**
     * Parent task identifier when this task is an occurrence in a recurring
     * series. Null identifies the parent occurrence or a one-time task.
     */
    @Nullable
    private Long parentTaskId;

    /**
     * Notifications associated with this task.
     *
     * <p>
     * Each notification is represented by a {@link ScheduledNotificationDTO}.
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private List<ScheduledNotificationDTO> notifications;

    /**
     * Flag indicating whether an update applies to only this task
     * or to the entire recurring series.
     *
     * <p>
     * Usage:
     * <ul>
     * <li>{@code true} → update all tasks in the series</li>
     * <li>{@code false/null} → update only this task</li>
     * </ul>
     * </p>
     */
    private Boolean updateSeries;

    /**
     * Date of the task creation in miliseconds.
     * <p>
     * </p>
     * <p>
     * </p>
     */
    private Long createdAt;
}
