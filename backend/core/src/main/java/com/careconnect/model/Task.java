package com.careconnect.model;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import com.careconnect.service.ai.RetrievalRecordChangeListener;

import io.micrometer.common.lang.Nullable;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Entity;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Entity class representing a task assigned to a patient.
 *
 * <p>
 * A {@code Task} can represent different activities such as
 * medications, appointments, exercises, labs, or general reminders.
 * It supports both one-time and recurring scheduling via frequency fields,
 * and can generate associated {@link ScheduledNotification}s.
 * </p>
 *
 * <p>
 * Relationships:
 * <ul>
 * <li>{@link Patient} – each task belongs to one patient</li>
 * <li>{@link ScheduledNotification} – each task may have multiple
 * notifications tied to it</li>
 * </ul>
 * </p>
 */

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "tasks")
@EntityListeners(RetrievalRecordChangeListener.class)
public class Task {

    /**
     * Primary key (auto-generated).
     */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Patient that this task belongs to.
     *
     * <p>
     * Each patient can have many tasks, but a task belongs to only one patient.
     * </p>
     *
     * <p>
     * Uses {@code EAGER} fetching to load patient details alongside the task.
     * </p>
     */
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "patient_id")
    private Patient patient;

    /**
     * Name of the task (e.g., "Take Blood Pressure Medication").
     */
    private String name;

    /**
     * Optional description providing more context for the task.
     */
    @Nullable
    private String description;

    /**
     * The date when the task is scheduled.
     * <p>
     * Stored as a string; should follow a consistent format
     * (e.g., ISO-8601) for proper parsing.
     * </p>
     */
    private String date;

    /**
     * Optional time of day when the task should be performed
     * (e.g., "08:30 AM").
     */
    @Nullable
    private String timeOfDay;

    /**
     * Whether the task has been completed.
     */
    private boolean isCompleted;

    /**
     * Type of task.
     * <p>
     * Examples: {@code "Medication"}, {@code "Appointment"},
     * {@code "Exercise"}, {@code "Lab"}, {@code "Pharmacy"}, {@code "General"}.
     * </p>
     */
    private String taskType;

    // ----------------------------
    // Recurrence / Frequency fields
    // ----------------------------

    /**
     * Frequency of recurrence (e.g., {@code "daily"}, {@code "weekly"}).
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
    private Integer taskInterval;

    /**
     * Number of times the task should repeat.
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private Integer doCount;

    /**
     * Days of the week the task should occur.
     * <p>
     * Typically stored as a serialized list (e.g., {@code "MON,WED,FRI"}).
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private String daysOfWeek;

    /**
     * Time of creation in miliseconds.
     */
    private Long createdAt;

    // ----------------------------
    // Relationships
    // ----------------------------

    /**
     * Notifications associated with this task.
     *
     * <p>
     * Each task may generate multiple {@link ScheduledNotification}s
     * for reminders and alerts.
     * </p>
     *
     * <p>
     * Details:
     * <ul>
     * <li>{@code mappedBy="task"} → owned by {@link ScheduledNotification}</li>
     * <li>{@code CascadeType.ALL} → notifications are created/removed with
     * task</li>
     * <li>{@code orphanRemoval=true} → deletes notifications if task reference is
     * removed</li>
     * <li>{@code FetchType.LAZY} → notifications loaded only when accessed</li>
     * </ul>
     * </p>
     */
    @OneToMany(mappedBy = "task", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @Builder.Default
    private List<ScheduledNotification> notifications = new ArrayList<>();

    // ----------------------------
    // Hierarchical Tasks
    // ----------------------------

    /**
     * Reference to a parent task if this task is part of a recurring series.
     *
     * <p>
     * Example: A "Daily Medication" parent task may generate child tasks
     * for individual days. The children reference the parent task’s ID here.
     * </p>
     * <p>
     * Optional.
     * </p>
     */
    @Nullable
    private Long parentTaskId;

}