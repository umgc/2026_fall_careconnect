package com.careconnect.service.v2;

import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.careconnect.dto.ScheduledNotificationDTO;
import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.exception.ParentTaskNotFoundException;
import com.careconnect.exception.PatientNotFoundException;
import com.careconnect.exception.TaskNotFoundException;
import com.careconnect.model.Patient;
import com.careconnect.model.ScheduledNotification;
import com.careconnect.model.Task;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.util.TaskMapper;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Service layer for managing tasks (API v2).
 *
 * <p>
 * This class contains business logic for creating, updating,
 * retrieving, and deleting tasks. It also handles recurrence
 * expansion, mapping between {@link Task} entities and
 * {@link TaskDtoV2} DTOs, and scheduling of associated
 * {@link ScheduledNotification}s.
 * </p>
 *
 * <p>
 * Key responsibilities:
 * <ul>
 * <li>CRUD operations on tasks</li>
 * <li>Recurrence expansion (daily, weekly, monthly, yearly)</li>
 * <li>Selective updates of recurring series</li>
 * <li>Mapping between entity and DTO representations</li>
 * <li>Notification management and time-shifting across occurrences</li>
 * </ul>
 * </p>
 */
@Service
@Transactional
public class TaskServiceV2 {

    private static final Logger log = LoggerFactory.getLogger(TaskServiceV2.class);
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ISO_LOCAL_DATE_TIME;
    private final ObjectMapper mapper;
    private TaskRepository taskRepository;
    private PatientRepository patientRepository;

    /**
     * Constructs the service with required repositories and mapper.
     *
     * @param taskRepository    repository for tasks
     * @param patientRepository repository for patients
     * @param mapper            Jackson object mapper
     */
    public TaskServiceV2(TaskRepository taskRepository, PatientRepository patientRepository, ObjectMapper mapper) {
        this.taskRepository = taskRepository;
        this.patientRepository = patientRepository;
        this.mapper = mapper;
    }

    private static LocalDate onlyDate(String isoDateOrDateTime) {
        // accepts "YYYY-MM-DD" or "YYYY-MM-DDTHH:mm..."
        return LocalDate.parse(isoDateOrDateTime.substring(0, 10));
    }

    private static boolean hasAnySelectedDay(List<Boolean> days) {
        if (days == null) {
            return false;
        }
        return days.stream().anyMatch(Boolean.TRUE::equals);
    }

    /**
     * Retrieves a task entity by its ID.
     *
     * @param taskId the ID of the task
     * @return the {@link Task} entity
     * @throws TaskNotFoundException if task not found
     */
    public Task getTaskById(Long taskId) {
        return taskRepository.findById(taskId)
                .orElseThrow(() -> new TaskNotFoundException(taskId));
    }

    /**
     * Retrieves a task as a DTO by its ID.
     *
     * @param taskId the ID of the task
     * @return the {@link TaskDtoV2}
     */
    public TaskDtoV2 getTaskDtoById(Long taskId) {
        Task task = getTaskById(taskId);
        return mapToDto(task);
    }

    /**
     * Retrieves all tasks for a given patient.
     *
     * @param patientId the ID of the patient
     * @return list of {@link TaskDtoV2} objects (empty if none found)
     */
    public List<TaskDtoV2> getTasksByPatient(Long patientId) {
        Optional<List<Task>> tasksOpt = taskRepository.findByPatientId(patientId);
        return tasksOpt.orElseGet(ArrayList::new).stream()
                .map(this::mapToDto)
                .toList();
    }

    /**
     * Creates a new task for a patient. Expands recurrence
     * into additional occurrences if defined.
     *
     * @param patientId the ID of the patient
     * @param taskDto   DTO containing task details
     * @return the created {@link TaskDtoV2}
     */
    public TaskDtoV2 createTask(Long patientId, TaskDtoV2 taskDto) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new PatientNotFoundException(patientId));

        log.info("Creating task for patient: " + patient.getId());
        log.debug("Task details: " + taskDto);

        // --- Normalize recurrence for imported/partial tasks --------------------
        if (taskDto.getFrequency() != null && taskDto.getCount() == null && taskDto.getDate() != null) {
            try {
                // Determine start and end (use start date + frequency to estimate)
                LocalDate startDate = LocalDate.parse(taskDto.getDate().substring(0, 10));

                // If frontend provided an implied end date (e.g., from UNTIL) inside
                // description or elsewhere,
                // you can skip this — otherwise default to a small horizon so backend can
                // compute count safely.
                LocalDate impliedEnd = startDate.plusMonths(3);

                int computedCount = calculateCount(
                        startDate,
                        impliedEnd,
                        taskDto.getFrequency(),
                        Optional.ofNullable(taskDto.getInterval()).orElse(1),
                        taskDto.getDaysOfWeek());

                taskDto.setCount(computedCount);
            } catch (Exception ex) {
                log.warn("Could not normalize recurrence count for imported task: " + ex.getMessage());
            }
        }

        Task parentTask = Task.builder()
                .name(taskDto.getName())
                .description(taskDto.getDescription())
                .date(taskDto.getDate())
                .createdAt(Instant.now().toEpochMilli())
                .timeOfDay(taskDto.getTimeOfDay())
                .isCompleted(taskDto.isCompleted())
                .frequency(taskDto.getFrequency())
                .taskInterval(taskDto.getInterval() != null ? taskDto.getInterval() : 0)
                .doCount(taskDto.getCount() != null ? taskDto.getCount() : 0)
                .daysOfWeek(TaskMapper.serializeDays(taskDto.getDaysOfWeek()))
                .taskType(taskDto.getTaskType())
                .patient(patient)
                .parentTaskId(null)
                .build();
        if (taskDto.getNotifications() != null && !taskDto.getNotifications().isEmpty()) {
            for (ScheduledNotificationDTO n : taskDto.getNotifications()) {
                ScheduledNotification sn = ScheduledNotification.builder()
                        .receiverId(n.getReceiverId())
                        .title(n.getTitle())
                        .body(n.getBody())
                        .notificationType(n.getNotificationType())
                        .scheduledTime(LocalDateTime.parse(n.getScheduledTime(), FORMATTER))
                        .status("PENDING")
                        .task(parentTask)
                        .build();

                parentTask.getNotifications().add(sn);
            }
        }
        Task savedParent = taskRepository.save(parentTask);
        log.info("New task created: " + parentTask);

        // Expand occurrences if recurrence is defined
        if (taskDto.getFrequency() != null && taskDto.getCount() != null && taskDto.getCount() > 1) {
            generateOccurrences(savedParent, taskDto, patient);
        }

        return mapToDto(savedParent);

    }

    /**
     * Updates the completion status of a specific task.
     *
     * <p>
     * This method retrieves the task by its unique identifier, updates its
     * {@code isComplete} flag to the given value, and persists the change to the
     * database. It is typically called when a user marks a task as complete or
     * incomplete from the front-end interface.
     * </p>
     *
     * <p>
     * This operation is transactional to ensure data consistency — if the task
     * is not found, a {@link TaskNotFoundException} is thrown and no changes are
     * committed.
     * </p>
     *
     * @param id         the unique identifier of the task to update
     * @param isComplete the new completion state (true = completed, false = not
     *                   completed)
     * @return a {@link TaskDtoV2} representing the updated task
     * @throws TaskNotFoundException if no task exists with the given ID
     */
    public TaskDtoV2 updateCompletionStatus(Long id, boolean isComplete) {
        Task task = taskRepository.findById(id)
                .orElseThrow(() -> new TaskNotFoundException(id));

        task.setCompleted(isComplete);
        Task saved = taskRepository.save(task);
        return mapToDto(saved);
    }

    /**
     * Updates a task. Can apply updates to a single task
     * or an entire recurring series based on {@code updateSeries}.
     *
     * @param taskId  ID of the task to update
     * @param taskDto updated task details
     * @return the updated {@link TaskDtoV2}
     */
    public TaskDtoV2 updateTask(Long taskId, TaskDtoV2 taskDto) {
        Task existingTask = getTaskById(taskId);

        if (!Boolean.TRUE.equals(taskDto.getUpdateSeries())) {
            // ---- Single-task update ----
            applyTaskUpdates(existingTask, taskDto, false);
            Task saved = taskRepository.save(existingTask);
            return mapToDto(saved);
        }

        // ---- SERIES UPDATE ----
        Long parentId = (existingTask.getParentTaskId() != null)
                ? existingTask.getParentTaskId()
                : existingTask.getId();

        Task parentTask = (existingTask.getParentTaskId() == null)
                ? existingTask
                : taskRepository.findById(parentId)
                .orElseThrow(() -> new ParentTaskNotFoundException(parentId));

        // Snapshot old recurrence fields BEFORE applying edits
        String originalParentDate = parentTask.getDate();
        String originalFreq = parentTask.getFrequency();
        Integer originalInterval = parentTask.getTaskInterval();
        Integer originalCount = parentTask.getDoCount();
        String originalDays = parentTask.getDaysOfWeek();

        // Original implied end before change
        LocalDate originalEnd = impliedEndDateFromSaved(parentTask);

        // Apply updates but preserve recurrence fields and start date if editing a
        // later occurrence
        applyTaskUpdates(parentTask, taskDto, true);

        // Force parent to keep its original recurrence anchor
        parentTask.setDate(originalParentDate);
        if (originalFreq != null)
            parentTask.setFrequency(originalFreq);
        if (originalInterval != null)
            parentTask.setTaskInterval(originalInterval);
        if (originalCount != null)
            parentTask.setDoCount(originalCount);
        if (originalDays != null)
            parentTask.setDaysOfWeek(originalDays);

        taskRepository.save(parentTask);
        // ---- Detect changes (compare DTO vs original series values) ----
        List<Boolean> originalDaysList = TaskMapper.parseDays(originalDays);

        boolean freqChanged = taskDto.getFrequency() != null &&
                !Objects.equals(
                        taskDto.getFrequency().toLowerCase(),
                        Optional.ofNullable(originalFreq).map(String::toLowerCase).orElse(null));

        boolean intvChanged = taskDto.getInterval() != null &&
                !Objects.equals(taskDto.getInterval(), originalInterval);

        boolean countChanged = taskDto.getCount() != null &&
                !Objects.equals(taskDto.getCount(), originalCount);

        boolean daysChanged = taskDto.getDaysOfWeek() != null &&
                !Objects.equals(taskDto.getDaysOfWeek(), originalDaysList);

        boolean recurrenceChanged = freqChanged || intvChanged || countChanged || daysChanged;

        // 2) Update children selectively
        List<Task> children = taskRepository.findByParentTaskId(parentId);

        if (recurrenceChanged) {
            // Recurrence-defining fields changed → wipe children and regenerate
            taskRepository.deleteAll(children);

            SeriesParams newParams = new SeriesParams(
                    onlyDate(parentTask.getDate()),
                    parentTask.getTimeOfDay() != null ? LocalTime.parse(parentTask.getTimeOfDay()) : null,
                    parentTask.getFrequency(),
                    Optional.ofNullable(parentTask.getTaskInterval()).orElse(1),
                    Optional.ofNullable(parentTask.getDoCount()).orElse(1),
                    TaskMapper.parseDays(parentTask.getDaysOfWeek()));

            LocalDate impliedEnd = impliedEndDateFromSaved(parentTask);
            if (taskDto.getDate() != null && taskDto.getCount() == null) {
                LocalDate newEnd = impliedEnd;
                LocalDate startDate = onlyDate(parentTask.getDate());
                int newCount = calculateCount(
                        startDate,
                        newEnd,
                        parentTask.getFrequency(),
                        Optional.ofNullable(parentTask.getTaskInterval()).orElse(1),
                        TaskMapper.parseDays(parentTask.getDaysOfWeek()));
                parentTask.setDoCount(newCount);
                taskRepository.save(parentTask);
                newParams = newParams.withCount(newCount);
            }
            List<LocalDate> targetDates = generateDates(newParams, null);
            if (!targetDates.isEmpty()) {
                LocalDate earliest = targetDates.get(0);
                LocalDate parentDate = onlyDate(parentTask.getDate());
                if (earliest.isBefore(parentDate)) {
                    log.info("Adjusting parent date from {} → {}", parentDate, earliest);
                    parentTask.setDate(earliest.toString());
                    taskRepository.save(parentTask);
                }
            }
            if ("weekly".equalsIgnoreCase(newParams.frequency) && daysChanged) {
                // Weekly days changed → keep the same calendar END, recompute COUNT
                int newCount = recomputeCountFromEnd(newParams, originalEnd);
                parentTask.setDoCount(newCount);
                taskRepository.save(parentTask);

                newParams = newParams.withCount(newCount);
                reconcileSeries(parentTask, newParams, originalEnd); // end-capped
            } else {
                // All other edits → use implied end from parentTask
                LocalDate afterEditEnd = impliedEndDateFromSaved(parentTask);
                reconcileSeries(parentTask, newParams, afterEditEnd);
            }

        } else {
            // Non-recurrence edits → update children safely
            for (Task child : children) {
                applySeriesFieldUpdatesToChild(child, taskDto,
                        taskDto.getName() != null,
                        taskDto.getDescription() != null,
                        taskDto.getTaskType() != null,
                        freqChanged, intvChanged, countChanged, daysChanged);
            }
            taskRepository.saveAll(children);
        }
        return mapToDto(parentTask);
    }

    /**
     * Calculates the total number of expected occurrences for a series,
     * given a start date, end date, frequency, and interval.
     *
     * <p>
     * Supports daily, weekly (with optional days-of-week mask), monthly, and
     * yearly.
     * </p>
     *
     * <ul>
     * <li><b>daily</b> – counts days between start and end, divided by
     * interval</li>
     * <li><b>weekly</b> – if daysOfWeek is provided, counts only matching weekdays;
     * otherwise counts whole weeks</li>
     * <li><b>monthly</b> – counts months between start and end, divided by
     * interval</li>
     * <li><b>yearly</b> – counts years between start and end, divided by
     * interval</li>
     * </ul>
     *
     * @param startDate  first occurrence date
     * @param endDate    inclusive last date
     * @param frequency  daily|weekly|monthly|yearly
     * @param interval   spacing between occurrences (≥1)
     * @param daysOfWeek for weekly recurrence: 7-length list (Sun=0..Sat=6); may be
     *                   null
     * @return number of expected occurrences (≥1)
     */
    private int calculateCount(LocalDate startDate, LocalDate endDate, String frequency,
                               int interval, List<Boolean> daysOfWeek) {
        switch (frequency.toLowerCase()) {
            case "daily":
                long days = Duration.between(startDate.atStartOfDay(), endDate.atStartOfDay()).toDays();
                return (int) (days / interval) + 1;
            case "weekly":
                if (daysOfWeek == null || daysOfWeek.isEmpty()) {
                    long weeks = Duration.between(startDate.atStartOfDay(), endDate.atStartOfDay()).toDays() / 7;
                    return (int) (weeks / interval) + 1;
                }
                int count = 0;
                LocalDate cursor = startDate;
                while (!cursor.isAfter(endDate)) {
                    int idx = (cursor.getDayOfWeek().getValue() % 7); // Sun=0…Sat=6
                    if (daysOfWeek.size() > idx && Boolean.TRUE.equals(daysOfWeek.get(idx))) {
                        count++;
                    }
                    cursor = cursor.plusDays(1);
                }
                return count;
            case "monthly":
                int months = (endDate.getYear() - startDate.getYear()) * 12
                        + (endDate.getMonthValue() - startDate.getMonthValue());
                return (months / interval) + 1;
            case "yearly":
                int years = endDate.getYear() - startDate.getYear();
                return (years / interval) + 1;
            default:
                return 1;
        }
    }

    /**
     * Applies selective updates from a parent DTO to a child task
     * in a recurring series.
     *
     * <p>
     * This method is used during series updates to propagate
     * only the fields that actually changed on the parent, leaving
     * other child-specific details untouched (e.g., completion state).
     * </p>
     *
     * @param task         the child {@link Task} to update
     * @param dto          the updated task DTO
     * @param nameChanged  whether the name field changed
     * @param descChanged  whether the description field changed
     * @param typeChanged  whether the task type field changed
     * @param freqChanged  whether the frequency field changed
     * @param intvChanged  whether the interval field changed
     * @param countChanged whether the occurrence count changed
     * @param daysChanged  whether the days-of-week field changed
     */
    private void applySeriesFieldUpdatesToChild(
            Task task, TaskDtoV2 dto,
            boolean nameChanged, boolean descChanged, boolean typeChanged,
            boolean freqChanged, boolean intvChanged, boolean countChanged, boolean daysChanged) {
        if (nameChanged)
            task.setName(dto.getName());
        if (descChanged)
            task.setDescription(dto.getDescription());
        if (typeChanged)
            task.setTaskType(dto.getTaskType());

        if (freqChanged)
            task.setFrequency(dto.getFrequency());
        if (intvChanged)
            task.setTaskInterval(dto.getInterval());
        if (countChanged)
            task.setDoCount(dto.getCount());
        if (daysChanged)
            task.setDaysOfWeek(TaskMapper.serializeDays(dto.getDaysOfWeek()));
    }

    /**
     * Deletes a task. If {@code deleteSeries} is true,
     * deletes the entire recurring series.
     *
     * @param taskId       ID of the task to delete
     * @param deleteSeries whether to delete just this task or the whole series
     */
    public void deleteTask(Long taskId, boolean deleteSeries) {
        Task task = getTaskById(taskId);

        if (deleteSeries) {
            Long parentId = task.getParentTaskId() != null
                    ? task.getParentTaskId()
                    : task.getId();

            List<Task> seriesTasks = taskRepository.findByParentTaskId(parentId);
            seriesTasks.add(taskRepository.findById(parentId)
                    .orElseThrow(() -> new ParentTaskNotFoundException(parentId)));

            taskRepository.deleteAll(seriesTasks);
            log.info(" Deleted series with parentId=" + parentId + " (count=" + seriesTasks.size() + ")");
        } else {
            if (task.getParentTaskId() == null) {
                // Deleting the parent but not the series → promote a child
                List<Task> children = taskRepository.findByParentTaskId(task.getId());
                if (!children.isEmpty()) {
                    Task newParent = children.get(0); // promote the first child
                    newParent.setParentTaskId(null);
                    taskRepository.save(newParent);

                    for (int i = 1; i < children.size(); i++) {
                        children.get(i).setParentTaskId(newParent.getId());
                    }
                    taskRepository.saveAll(children.subList(1, children.size()));
                    log.info("Promoted child " + newParent.getId() + " as new parent for series");
                }
            }
            taskRepository.delete(task);
            log.info("Deleted single task id=" + taskId);
        }
    }

    // -----------------------------
    // Private helpers (mapping, recurrence, updates)
    // -----------------------------

    /**
     * Checks if a task exists by ID.
     *
     * @param taskId the task ID
     * @return true if found, false otherwise
     */
    public boolean existsById(Long taskId) {
        return taskRepository.findById(taskId).isPresent();
    }

    /**
     * Retrieves all tasks in the system.
     *
     * @return list of all {@link TaskDtoV2}
     * @throws TaskNotFoundException if no tasks exist
     */
    public List<TaskDtoV2> getAllTasks() {
        List<Task> tasks = taskRepository.findAll();
        if (tasks.isEmpty()) {
            throw new TaskNotFoundException("No tasks found");
        }
        return tasks.stream().map(this::mapToDto).toList();
    }

    /**
     * Maps a {@link Task} entity to a {@link TaskDtoV2}.
     */
    private TaskDtoV2 mapToDto(Task task) {
        return TaskDtoV2.builder()
                .id(task.getId())
                .name(task.getName())
                .description(task.getDescription())
                .date(task.getDate())
                .createdAt(task.getCreatedAt())
                .timeOfDay(task.getTimeOfDay())
                .isCompleted(task.isCompleted())
                .frequency(task.getFrequency())
                .interval(task.getTaskInterval())
                .count(task.getDoCount())
                .daysOfWeek(TaskMapper.parseDays(task.getDaysOfWeek()))
                .taskType(task.getTaskType())
                .patientId(task.getPatient() != null ? task.getPatient().getId() : null)
                .notifications(task.getNotifications() != null
                        ? task.getNotifications().stream()
                        .map(n -> new ScheduledNotificationDTO(
                                n.getReceiverId(),
                                n.getTitle(),
                                n.getBody(),
                                n.getNotificationType(),
                                n.getScheduledTime() != null ? n.getScheduledTime().toString() : null))
                        .toList()
                        : null)
                .build();
    }

    /**
     * Generates missing occurrences of a recurring task series.
     */
    private void generateOccurrences(Task parentTask, TaskDtoV2 dto, Patient patient) {
        List<LocalDate> expectedDates = calculateExpectedDates(dto);
        if (expectedDates.isEmpty())
            return;

        LocalDate startDate = LocalDate.parse(dto.getDate().substring(0, 10));
        LocalTime baseTime = (dto.getTimeOfDay() != null)
                ? LocalTime.parse(dto.getTimeOfDay())
                : LocalTime.MIDNIGHT;
        LocalDateTime baseDateTime = startDate.atTime(baseTime);

        Long parentId = parentTask.getParentTaskId() != null
                ? parentTask.getParentTaskId()
                : parentTask.getId();

        // Load existing occurrences for this series only
        List<Task> existing = taskRepository.findByParentTaskId(parentId);
        existing.add(parentTask);

        // Track existing by (parentIdOrSelf, date)
        Set<String> existingKeys = existing.stream()
                .map(t -> {
                    String d = t.getDate();
                    String normalized = (d != null && d.length() >= 10) ? d.substring(0, 10) : d;
                    return parentId + "|" + normalized;
                })
                .collect(Collectors.toSet());

        List<Task> newOnes = new ArrayList<>();

        for (LocalDate occurrenceDate : expectedDates) {
            String key = parentId + "|" + occurrenceDate.toString();
            if (!existingKeys.contains(key)) {
                newOnes.add(buildOccurrence(parentTask, dto, patient, baseDateTime, occurrenceDate));
            }
        }

        if (!newOnes.isEmpty()) {
            taskRepository.saveAll(newOnes);
            log.info("Added " + newOnes.size() + " new occurrences to series " + parentTask.getId());
        }
    }

    /**
     * Applies updates from a DTO to a task.
     *
     * @param task         task entity to update
     * @param dto          DTO with updates
     * @param updateSeries whether to allow updates of recurrence fields
     */
    private void applyTaskUpdates(Task task, TaskDtoV2 dto, boolean updateSeries) {
        // Patient assignment only if explicitly set
        if (dto.getPatientId() != null) {
            Patient newPatient = patientRepository.findById(dto.getPatientId())
                    .orElseThrow(() -> new PatientNotFoundException(dto.getPatientId()));
            task.setPatient(newPatient);
        }

        // Only override if non-null in DTO
        if (dto.getName() != null) {
            task.setName(dto.getName());
        }
        if (dto.getDescription() != null) {
            task.setDescription(dto.getDescription());
        }

        // completed is boolean, so always set (if you want to respect one-off,
        // you could add Boolean wrapper in TaskDtoV2 instead of primitive)
        task.setCompleted(dto.isCompleted());

        if (dto.getTaskType() != null) {
            task.setTaskType(dto.getTaskType());
        }

        if (updateSeries) {
            if (dto.getFrequency() != null) {
                task.setFrequency(dto.getFrequency());
            }
            if (dto.getInterval() != null) {
                task.setTaskInterval(dto.getInterval());
            }
            if (dto.getCount() != null) {
                task.setDoCount(dto.getCount());
            }
            if (dto.getDaysOfWeek() != null) {
                task.setDaysOfWeek(TaskMapper.serializeDays(dto.getDaysOfWeek()));
            }

            // Parent should stay anchored to earliest occurrence
            if (task.getParentTaskId() == null) {
                if (dto.getDate() != null) {
                    if ("monthly".equalsIgnoreCase(task.getFrequency())
                            || "yearly".equalsIgnoreCase(task.getFrequency())) {
                        // Always allow updating parent date to new selected day
                        task.setDate(dto.getDate());
                    } else {
                        LocalDate newStart = LocalDate.parse(dto.getDate().substring(0, 10));
                        LocalDate currentParent = LocalDate.parse(task.getDate().substring(0, 10));
                        if (newStart.isBefore(currentParent)) {
                            task.setDate(dto.getDate());
                        }
                    }
                }
                if (dto.getTimeOfDay() != null) {
                    task.setTimeOfDay(dto.getTimeOfDay());
                }
            }
        } else {
            // One-off edits
            if (dto.getDate() != null) {
                task.setDate(dto.getDate());
            }
            if (dto.getTimeOfDay() != null) {
                task.setTimeOfDay(dto.getTimeOfDay());
            }
            if (dto.getFrequency() != null) {
                task.setFrequency(dto.getFrequency());
            }
            if (dto.getInterval() != null) {
                task.setTaskInterval(dto.getInterval());
            }
            if (dto.getCount() != null) {
                task.setDoCount(dto.getCount());
            }
            if (dto.getDaysOfWeek() != null) {
                task.setDaysOfWeek(TaskMapper.serializeDays(dto.getDaysOfWeek()));
            }
        }

        // Notifications (replace only if explicitly passed)
        if (dto.getNotifications() != null) {
            if (task.getNotifications() == null) {
                task.setNotifications(new ArrayList<>());
            } else {
                task.getNotifications().clear();
            }

            for (ScheduledNotificationDTO n : dto.getNotifications()) {
                ScheduledNotification sn = ScheduledNotification.builder()
                        .receiverId(n.getReceiverId())
                        .title(n.getTitle())
                        .body(n.getBody())
                        .notificationType(n.getNotificationType())
                        .scheduledTime(LocalDateTime.parse(n.getScheduledTime(), FORMATTER))
                        .status("PENDING")
                        .task(task)
                        .build();
                task.getNotifications().add(sn);
            }
        }
    }
    // --- Utilities ---------------------------------------------------------------

    /**
     * Builds a new recurring occurrence based on parent task and DTO.
     */
    private Task buildOccurrence(Task parentTask, TaskDtoV2 dto, Patient patient,
                                 LocalDateTime baseDateTime, LocalDate occurrenceDate) {

        LocalTime occTime = (dto.getTimeOfDay() != null)
                ? LocalTime.parse(dto.getTimeOfDay())
                : LocalTime.MIDNIGHT;
        LocalDateTime occurrenceDateTime = occurrenceDate.atTime(occTime);

        Task occurrence = Task.builder()
                .name(dto.getName())
                .description(dto.getDescription())
                .date(occurrenceDate.toString())
                .timeOfDay(dto.getTimeOfDay())
                .isCompleted(false)
                .taskType(dto.getTaskType())
                .frequency(dto.getFrequency())
                .taskInterval(dto.getInterval())
                .doCount(dto.getCount())
                .daysOfWeek(TaskMapper.serializeDays(dto.getDaysOfWeek()))
                .patient(patient)
                .parentTaskId(parentTask.getId())
                .build();

        // Notifications: shift relative to base
        if (dto.getNotifications() != null && !dto.getNotifications().isEmpty()) {
            for (ScheduledNotificationDTO n : dto.getNotifications()) {
                LocalDateTime originalScheduledTime = LocalDateTime.parse(n.getScheduledTime(), FORMATTER);
                Duration offset = Duration.between(baseDateTime, originalScheduledTime);

                LocalDateTime adjustedTime = occurrenceDateTime.plus(offset);

                ScheduledNotification sn = ScheduledNotification.builder()
                        .receiverId(n.getReceiverId())
                        .title(n.getTitle())
                        .body(n.getBody())
                        .notificationType(n.getNotificationType())
                        .scheduledTime(adjustedTime)
                        .status("PENDING")
                        .task(occurrence)
                        .build();

                occurrence.getNotifications().add(sn);
            }
        }

        return occurrence;
    }

    /**
     * Calculates expected occurrence dates for a recurring task.
     *
     * <p>
     * Supports daily, weekly, monthly, yearly frequencies.
     * </p>
     */
    private List<LocalDate> calculateExpectedDates(TaskDtoV2 dto) {
        LocalDate startDate = LocalDate.parse(dto.getDate().substring(0, 10));
        int interval = (dto.getInterval() != null && dto.getInterval() > 0) ? dto.getInterval() : 1;
        int count = dto.getCount() != null ? dto.getCount() : 1;

        List<LocalDate> dates = new ArrayList<>();

        switch (dto.getFrequency().toLowerCase()) {
            case "daily" -> {
                for (int i = 0; i < count; i++) {
                    dates.add(startDate.plusDays(i * interval));
                }
            }
            case "weekly" -> {
                List<Boolean> daysOfWeek = dto.getDaysOfWeek();
                if (daysOfWeek == null || daysOfWeek.size() < 7 || !hasAnySelectedDay(daysOfWeek))
                    return dates;

                int created = 0;
                LocalDate weekCursor = startDate;

                while (created < count) {
                    LocalDate weekStart = weekCursor.with(DayOfWeek.SUNDAY);
                    for (int i = 0; i < 7 && created < count; i++) {
                        if (Boolean.TRUE.equals(daysOfWeek.get(i))) {
                            DayOfWeek targetDOW = DayOfWeek.of(((i + 6) % 7) + 1);
                            LocalDate occurrenceDate = weekStart.with(targetDOW);

                            if (!occurrenceDate.isBefore(startDate)) {
                                dates.add(occurrenceDate);
                                created++;
                            }
                        }
                    }
                    weekCursor = weekCursor.plusWeeks(interval);
                }
            }
            case "monthly" -> {
                for (int i = 0; i < count; i++) {
                    dates.add(startDate.plusMonths(i * interval));
                }
            }
            case "yearly" -> {
                for (int i = 0; i < count; i++) {
                    dates.add(startDate.plusYears(i * interval));
                }
            }
        }
        return dates;
    }

    /**
     * Build the full list of occurrence dates either by COUNT (endCap=null) or by
     * END cap (inclusive).
     */
    private List<LocalDate> generateDates(SeriesParams p, LocalDate endCap) {
        List<LocalDate> out = new ArrayList<>();

        switch (p.frequency.toLowerCase()) {
            case "daily" -> {
                if (endCap != null) {
                    for (LocalDate d = p.startDate; !d.isAfter(endCap); d = d.plusDays(p.interval)) {
                        out.add(d);
                    }
                } else {
                    for (int i = 0; i < p.count; i++) {
                        out.add(p.startDate.plusDays((long) i * p.interval));
                    }
                }
            }
            case "weekly" -> {
                List<Boolean> days = p.days;
                if (days == null || days.size() != 7) {
                    // fallback to simple weekly step-by-step if days are missing
                    if (endCap != null) {
                        for (LocalDate d = p.startDate; !d.isAfter(endCap); d = d.plusWeeks(p.interval)) {
                            out.add(d);
                        }
                    } else {
                        for (int i = 0; i < p.count; i++) {
                            out.add(p.startDate.plusWeeks((long) i * p.interval));
                        }
                    }
                    break;
                }
                if (!hasAnySelectedDay(days)) {
                    // Invalid weekly mask: avoid infinite loops by returning no occurrences.
                    break;
                }

                // Iterate week by week starting from the week containing startDate.
                LocalDate cursor = p.startDate;
                int made = 0;
                int weeklyIterations = 0;
                int maxWeeklyIterations = (endCap != null)
                        ? Math.max(1, (int) Duration.between(
                        p.startDate.atStartOfDay(),
                        endCap.plusDays(1).atStartOfDay()).toDays() / 7 + 2)
                        : Math.max(8, p.count * 8);
                while (weeklyIterations++ < maxWeeklyIterations) {
                    LocalDate weekStart = cursor.with(DayOfWeek.SUNDAY);
                    if (endCap != null && weekStart.isAfter(endCap)) {
                        return out;
                    }
                    for (int i = 0; i < 7; i++) {
                        if (Boolean.TRUE.equals(days.get(i))) {
                            // Map i=0..6 (Sun..Sat) -> DayOfWeek (Mon=1..Sun=7)
                            DayOfWeek dow = DayOfWeek.of(((i + 6) % 7) + 1);
                            LocalDate occ = weekStart.with(dow);
                            if (!occ.isBefore(p.startDate)) {
                                if (endCap != null) {
                                    if (occ.isAfter(endCap)) {
                                        // If same day as endCap, still include
                                        if (!occ.isEqual(endCap))
                                            return out;
                                    }
                                    out.add(occ);
                                } else {
                                    out.add(occ);
                                    made++;
                                    if (made >= p.count)
                                        return out;
                                }
                            }
                        }
                    }
                    cursor = cursor.plusWeeks(p.interval);
                }
                return out;
            }
            case "monthly" -> {
                if (endCap != null) {
                    for (LocalDate d = p.startDate; !d.isAfter(endCap); d = d.plusMonths(p.interval)) {
                        out.add(d);
                    }
                } else {
                    for (int i = 0; i < p.count; i++) {
                        out.add(p.startDate.plusMonths((long) i * p.interval));
                    }
                }
            }
            case "yearly" -> {
                if (endCap != null) {
                    for (LocalDate d = p.startDate; !d.isAfter(endCap); d = d.plusYears(p.interval)) {
                        out.add(d);
                    }
                } else {
                    for (int i = 0; i < p.count; i++) {
                        out.add(p.startDate.plusYears((long) i * p.interval));
                    }
                }
            }
            default -> {
                // Unknown frequency: treat as one-time
                out.add(p.startDate);
            }
        }
        return out;
    }

    /**
     * End of current saved series = last date from (parent + count).
     */
    private LocalDate impliedEndDateFromSaved(Task parent) {
        SeriesParams p = new SeriesParams(
                onlyDate(parent.getDate()),
                parent.getTimeOfDay() != null ? LocalTime.parse(parent.getTimeOfDay()) : null,
                parent.getFrequency(),
                Optional.ofNullable(parent.getTaskInterval()).orElse(1),
                Optional.ofNullable(parent.getDoCount()).orElse(1),
                TaskMapper.parseDays(parent.getDaysOfWeek()));
        List<LocalDate> dates = generateDates(p, null);
        return dates.isEmpty() ? onlyDate(parent.getDate()) : dates.get(dates.size() - 1);
    }

    /**
     * Count given a target end cap.
     */
    private int recomputeCountFromEnd(SeriesParams params, LocalDate endCap) {
        return generateDates(params, endCap).size();
    }

    /**
     * Make DB occurrences match exactly the target dates (add missing, delete
     * extras).
     */
    private void reconcileSeries(Task parentTask, SeriesParams params, LocalDate endCap) {
        Long parentId = parentTask.getParentTaskId() != null ? parentTask.getParentTaskId() : parentTask.getId();

        List<LocalDate> target = generateDates(params, endCap);
        Set<String> targetKeys = target.stream().map(LocalDate::toString).collect(Collectors.toSet());

        // Load existing series (parent + children)
        List<Task> existing = taskRepository.findByParentTaskId(parentId);
        existing.add(parentTask);

        LocalDate parentStart = params.startDate;

        // Index by date (YYYY-MM-DD)
        var byDate = existing.stream().collect(Collectors.toMap(
                t -> onlyDate(t.getDate()).toString(),
                t -> t,
                (a, b) -> a));

        // ADD missing
        List<Task> toAdd = new ArrayList<>();
        for (LocalDate day : target) {
            String key = day.toString();
            if (!byDate.containsKey(key)) {
                Task occ = Task.builder()
                        .name(parentTask.getName())
                        .description(parentTask.getDescription())
                        .date(day.toString())
                        .timeOfDay(parentTask.getTimeOfDay())
                        .isCompleted(false)
                        .taskType(parentTask.getTaskType())
                        .frequency(parentTask.getFrequency())
                        .taskInterval(parentTask.getTaskInterval())
                        .doCount(parentTask.getDoCount())
                        .daysOfWeek(parentTask.getDaysOfWeek())
                        .patient(parentTask.getPatient())
                        .parentTaskId(parentId)
                        .build();
                toAdd.add(occ);
            }
        }

        // DELETE extras
        List<Task> toDelete = existing.stream()
                .filter(t -> {
                    String key = onlyDate(t.getDate()).toString();
                    boolean isParent = Objects.equals(t.getId(), parentTask.getId());

                    // Rule 1: delete if not in target list
                    if (!isParent && !targetKeys.contains(key)) {
                        return true;
                    }

                    // Rule 2: delete if before parent anchor
                    LocalDate occDate = onlyDate(t.getDate());
                    if (!isParent && occDate.isBefore(parentStart)) {
                        return true;
                    }

                    return false;
                })
                .toList();

        if (!toAdd.isEmpty()) {
            taskRepository.saveAll(toAdd);
            log.info("Reconcile: added {} new tasks", toAdd.size());
        }
        if (!toDelete.isEmpty()) {
            taskRepository.deleteAll(toDelete);
            log.info("Reconcile: deleted {} old tasks", toDelete.size());
        }
        // -------------------------------------------------------
        // Safety check: ensure full recurrence count exists
        // -------------------------------------------------------
        List<Task> currentSeries = taskRepository.findByParentTaskId(parentId);
        int expectedCount = Optional.ofNullable(parentTask.getDoCount()).orElse(1);

        // +1 accounts for the parent itself
        if (currentSeries.size() + 1 < expectedCount) {
            log.warn("Series undercount detected (have {}, expected {}). Rebuilding...",
                    currentSeries.size() + 1, expectedCount);

            // Regenerate any missing occurrences
            generateOccurrences(parentTask, mapToDto(parentTask), parentTask.getPatient());
        }

        if (currentSeries.size() + 1 < expectedCount) {
            log.warn("Series undercount detected (have {}, expected {}). Rebuilding...",
                    currentSeries.size() + 1, expectedCount);
            generateOccurrences(parentTask, mapToDto(parentTask), parentTask.getPatient());
        } else {
            log.info("Series count OK (have {}, expected {})",
                    currentSeries.size() + 1, expectedCount);
        }

    }

    /**
     * Parameters that define a recurrence.
     */
    private static final class SeriesParams {
        final LocalDate startDate; // parent date (first occurrence)
        final LocalTime time; // may be null
        final String frequency; // daily|weekly|monthly|yearly
        final int interval; // >= 1
        final int count; // >= 1
        final List<Boolean> days; // weekly: length=7 (Sun..Sat), else null

        SeriesParams(LocalDate startDate, LocalTime time, String frequency,
                     int interval, int count, List<Boolean> days) {
            this.startDate = startDate;
            this.time = time;
            this.frequency = frequency != null ? frequency : "daily";
            this.interval = Math.max(1, interval);
            this.count = Math.max(1, count);
            this.days = days;
        }

        SeriesParams withCount(int newCount) {
            return new SeriesParams(startDate, time, frequency, interval, Math.max(1, newCount), days);
        }
    }

}
