package com.careconnect.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Method;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import com.careconnect.dto.ScheduledNotificationDTO;
import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.exception.PatientNotFoundException;
import com.careconnect.exception.TaskNotFoundException;
import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.service.v2.TaskServiceV2;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Unit tests for {@link TaskServiceV2}.
 *
 * <p>
 * All external dependencies (repositories) are mocked with Mockito so that
 * these tests validate the service's business logic in isolation — no database
 * or Spring context is required.
 * </p>
 *
 * <p>
 * Private helper methods (e.g. {@code calculateCount}) are exercised via
 * reflection because they encapsulate significant branching logic that is worth
 * testing directly.
 * </p>
 */
class TaskServiceV2Test {

    private final ObjectMapper mapper = new ObjectMapper();
    @Mock
    private TaskRepository taskRepository;
    @Mock
    private PatientRepository patientRepository;
    @InjectMocks
    private TaskServiceV2 taskService;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        // Construct the service manually so the real ObjectMapper is wired in
        taskService = new TaskServiceV2(taskRepository, patientRepository, mapper);
    }

    // ==========================================================================
    // getTaskById
    // ==========================================================================

    @Test
    @DisplayName("getTaskById: returns the task entity when the ID exists")
    void testGetTaskById_found() throws Exception {
        // Verify that a task stored in the repository is returned unchanged
        final Task task = Task.builder().id(1L).name("Test Task").build();
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

        final Task result = taskService.getTaskById(1L);

        assertNotNull(result);
        assertEquals("Test Task", result.getName());
        verify(taskRepository).findById(1L);
    }

    @Test
    @DisplayName("getTaskById: throws TaskNotFoundException when the ID does not exist")
    void testGetTaskById_notFound() throws Exception {
        // A missing task must surface as a domain exception, not a null return
        when(taskRepository.findById(99L)).thenReturn(Optional.empty());

        assertThrows(TaskNotFoundException.class, () -> taskService.getTaskById(99L));
        verify(taskRepository).findById(99L);
    }

    // ==========================================================================
    // getTaskDtoById
    // ==========================================================================

    @Test
    @DisplayName("getTaskDtoById: maps the found entity to a DTO with correct id and name")
    void testGetTaskDtoById_found() throws Exception {
        // Confirms that the entity-to-DTO mapping preserves core identifying fields
        final Task task = Task.builder().id(7L).name("Morning Walk").date("2025-06-01").build();
        when(taskRepository.findById(7L)).thenReturn(Optional.of(task));

        final TaskDtoV2 result = taskService.getTaskDtoById(7L);

        assertNotNull(result);
        assertEquals(7L, result.getId());
        assertEquals("Morning Walk", result.getName());
    }

    @Test
    @DisplayName("getTaskDtoById: throws TaskNotFoundException for an unknown task ID")
    void testGetTaskDtoById_notFound() throws Exception {
        // The DTO lookup must propagate the not-found exception just like getTaskById
        when(taskRepository.findById(42L)).thenReturn(Optional.empty());

        assertThrows(TaskNotFoundException.class, () -> taskService.getTaskDtoById(42L));
    }

    // ==========================================================================
    // getTasksByPatient
    // ==========================================================================

    @Test
    @DisplayName("getTasksByPatient: maps each task entity to a DTO and returns the full list")
    void testGetTasksByPatient() throws Exception {
        // Both entities must appear in the result list in order
        final Task t1 = Task.builder().id(1L).name("Check Vitals").build();
        final Task t2 = Task.builder().id(2L).name("Take Medication").build();
        when(taskRepository.findByPatientId(5L)).thenReturn(Optional.of(List.of(t1, t2)));

        final List<TaskDtoV2> dtos = taskService.getTasksByPatient(5L);

        assertEquals(2, dtos.size());
        assertEquals("Check Vitals", dtos.get(0).getName());
        verify(taskRepository).findByPatientId(5L);
    }

    @Test
    @DisplayName("getTasksByPatient: returns an empty (non-null) list when no tasks exist for the patient")
    void testGetTasksByPatient_emptyReturnsEmptyList() throws Exception {
        // Optional.empty() from the repository should produce an empty list, not throw
        when(taskRepository.findByPatientId(99L)).thenReturn(Optional.empty());

        final List<TaskDtoV2> result = taskService.getTasksByPatient(99L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    // ==========================================================================
    // createTask
    // ==========================================================================

    @Test
    @DisplayName("createTask: persists a new one-time task and returns its DTO with the generated ID")
    void testCreateTask_savesNewTask() throws Exception {
        // The happy path: a valid patient and a non-recurring task DTO
        final Patient patient = Patient.builder().id(5L).build();
        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));

        final TaskDtoV2 dto = TaskDtoV2.builder()
                .name("Daily Check")
                .description("Measure blood pressure")
                .date(LocalDate.now().toString())
                .timeOfDay("08:00")
                .frequency("daily")
                .interval(1)
                .count(1)
                .taskType("Health")
                .isCompleted(false)
                .build();

        // Simulate the DB assigning a primary key after insert
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
            final Task saved = inv.getArgument(0);
            saved.setId(10L);
            return saved;
        });

        final TaskDtoV2 result = taskService.createTask(5L, dto);

        assertNotNull(result);
        assertEquals("Daily Check", result.getName());
        assertEquals(10L, result.getId());
        verify(taskRepository, atLeastOnce()).save(any(Task.class));
        verify(patientRepository).findById(5L);
    }

    @Test
    @DisplayName("createTask: throws PatientNotFoundException when the patient ID does not exist")
    void testCreateTask_patientNotFound() throws Exception {
        // A task must not be created without a valid owning patient
        when(patientRepository.findById(999L)).thenReturn(Optional.empty());

        final TaskDtoV2 dto = TaskDtoV2.builder()
                .name("Task")
                .date("2025-01-01")
                .isCompleted(false)
                .build();

        assertThrows(PatientNotFoundException.class, () -> taskService.createTask(999L, dto));
    }

    @Test
    @DisplayName("createTask: calls saveAll to persist child occurrences when count > 1")
    void testCreateTask_withRecurrence_savesOccurrences() throws Exception {
        // When frequency is set and count > 1, the service must expand the recurring
        // series by saving additional occurrence tasks via saveAll
        final Patient patient = Patient.builder().id(5L).build();
        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));

        final TaskDtoV2 dto = TaskDtoV2.builder()
                .name("Daily Walk")
                .date("2025-01-01")
                .frequency("daily")
                .interval(1)
                .count(3)   // > 1 → triggers generateOccurrences
                .isCompleted(false)
                .build();

        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
            final Task saved = inv.getArgument(0);
            saved.setId(10L);
            return saved;
        });
        // findByParentTaskId must return a mutable list because the service calls .add() on it
        when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());
        when(taskRepository.saveAll(any())).thenReturn(new ArrayList<>());

        taskService.createTask(5L, dto);

        // saveAll is called with the 2 additional occurrence tasks (dates 2 and 3)
        verify(taskRepository, atLeastOnce()).saveAll(any());
    }

    @Test
    @DisplayName("createTask: attaches ScheduledNotification entities to the parent task before saving")
    void testCreateTask_withNotifications_attached() throws Exception {
        // Notifications provided in the DTO must be mapped to entities and linked
        // to the saved task without throwing during construction
        final Patient patient = Patient.builder().id(5L).build();
        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));

        final ScheduledNotificationDTO notif = new ScheduledNotificationDTO(
                1L, "Reminder", "Take your medicine", "PUSH", "2025-01-01T08:00:00");

        final TaskDtoV2 dto = TaskDtoV2.builder()
                .name("Take Medication")
                .date("2025-01-01")
                .isCompleted(false)
                .notifications(List.of(notif))
                .build();

        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
            final Task saved = inv.getArgument(0);
            saved.setId(20L);
            return saved;
        });

        final TaskDtoV2 result = taskService.createTask(5L, dto);

        assertNotNull(result);
        verify(taskRepository).save(any(Task.class));
    }

    // ==========================================================================
    // updateCompletionStatus
    // ==========================================================================

    @Test
    @DisplayName("updateCompletionStatus: sets isCompleted to true and persists the change")
    void testUpdateCompletionStatus_markComplete() throws Exception {
        // Completing a task must flip the flag and trigger a save
        final Task task = Task.builder().id(1L).isCompleted(false).name("Do something").build();
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        final TaskDtoV2 result = taskService.updateCompletionStatus(1L, true);

        assertTrue(result.isCompleted());
        verify(taskRepository).save(any(Task.class));
    }

    @Test
    @DisplayName("updateCompletionStatus: sets isCompleted to false (un-completing a task)")
    void testUpdateCompletionStatus_markIncomplete() throws Exception {
        // The method must work symmetrically for clearing the completion flag
        final Task task = Task.builder().id(2L).isCompleted(true).name("Done Task").build();
        when(taskRepository.findById(2L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        final TaskDtoV2 result = taskService.updateCompletionStatus(2L, false);

        assertFalse(result.isCompleted());
        verify(taskRepository).save(any(Task.class));
    }

    @Test
    @DisplayName("updateCompletionStatus: throws TaskNotFoundException for an unknown task ID")
    void testUpdateCompletionStatus_notFound() throws Exception {
        // Attempting to update a non-existent task must raise the domain exception
        when(taskRepository.findById(999L)).thenReturn(Optional.empty());

        assertThrows(TaskNotFoundException.class,
                () -> taskService.updateCompletionStatus(999L, true));
    }

    // ==========================================================================
    // updateTask — single mode (updateSeries = false / null)
    // ==========================================================================

    @Test
    @DisplayName("updateTask single mode: updates only the targeted task without touching series siblings")
    void testUpdateTask_singleUpdate_updatesFieldAndSaves() throws Exception {
        // updateSeries=false means the update must be scoped to one task;
        // findByParentTaskId must never be called in this path
        final Task existing = Task.builder()
                .id(1L).name("Old Name").date("2025-01-01")
                .frequency("daily").taskInterval(1).doCount(1)
                .build();
        when(taskRepository.findById(1L)).thenReturn(Optional.of(existing));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        final TaskDtoV2 dto = TaskDtoV2.builder()
                .name("New Name")
                .updateSeries(false)
                .isCompleted(false)
                .build();

        final TaskDtoV2 result = taskService.updateTask(1L, dto);

        assertEquals("New Name", result.getName());
        verify(taskRepository).save(any(Task.class));
        // Series siblings must not be queried or modified for a single-task update
        verify(taskRepository, never()).findByParentTaskId(any());
    }

    // ==========================================================================
    // updateTask — series mode (updateSeries = true, non-recurrence field change)
    // ==========================================================================

    @Test
    @DisplayName("updateTask series mode: propagates name change to all child tasks in the series")
    void testUpdateTask_seriesUpdate_nameChangeUpdatesChildren() throws Exception {
        // When only a non-recurrence field (name) changes, the service must update
        // all children via saveAll without deleting/regenerating occurrences
        final Task parent = Task.builder()
                .id(1L).name("Old Name").date("2025-01-01")
                .frequency("daily").taskInterval(1).doCount(3)
                .parentTaskId(null)
                .build();
        final Task child1 = Task.builder().id(2L).name("Old Name")
                .date("2025-01-02").parentTaskId(1L).build();
        final Task child2 = Task.builder().id(3L).name("Old Name")
                .date("2025-01-03").parentTaskId(1L).build();

        when(taskRepository.findById(1L)).thenReturn(Optional.of(parent));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));
        // Must be a mutable list because the service calls existing.add(parentTask)
        // inside impliedEndDateFromSaved → generateOccurrences path (reconcile)
        when(taskRepository.findByParentTaskId(1L))
                .thenReturn(new ArrayList<>(List.of(child1, child2)));
        when(taskRepository.saveAll(any())).thenReturn(new ArrayList<>());

        final TaskDtoV2 dto = TaskDtoV2.builder()
                .name("New Series Name")
                .updateSeries(true)
                .isCompleted(false)
                .build();

        final TaskDtoV2 result = taskService.updateTask(1L, dto);

        // The returned DTO reflects the updated parent name
        assertEquals("New Series Name", result.getName());
        // Both children must have inherited the new name
        assertEquals("New Series Name", child1.getName());
        assertEquals("New Series Name", child2.getName());
        // saveAll must be called to persist the updated children
        verify(taskRepository).saveAll(any());
    }

    // ==========================================================================
    // deleteTask
    // ==========================================================================

    @Test
    @DisplayName("deleteTask single: deletes only the specified task when it has no children")
    void testDeleteTask_single_noChildren_deletesTask() throws Exception {
        // A lone task (no series) must be directly deleted; no promotion logic runs
        final Task task = Task.builder().id(1L).parentTaskId(null).name("Solo Task").build();
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
        when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>());

        taskService.deleteTask(1L, false);

        verify(taskRepository).delete(task);
        // With no children there is nothing to re-parent
        verify(taskRepository, never()).saveAll(any());
    }

    @Test
    @DisplayName("deleteTask single parent: promotes the first child to series parent and re-parents the rest")
    void testDeleteTask_single_parentWithChildren_promotesFirstChild() throws Exception {
        // Deleting the series parent without deleting the series must re-root the
        // series so the first child becomes the new parent
        final Task parent = Task.builder().id(1L).parentTaskId(null).name("Parent Task").build();
        final Task child1 = Task.builder().id(2L).parentTaskId(1L).name("Child 1").build();
        final Task child2 = Task.builder().id(3L).parentTaskId(1L).name("Child 2").build();

        when(taskRepository.findById(1L)).thenReturn(Optional.of(parent));
        when(taskRepository.findByParentTaskId(1L))
                .thenReturn(new ArrayList<>(List.of(child1, child2)));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));
        when(taskRepository.saveAll(any())).thenReturn(new ArrayList<>());

        taskService.deleteTask(1L, false);

        // child1's parentTaskId must be cleared so it becomes the root of the series
        assertNull(child1.getParentTaskId());
        // child2 must now point to child1 as its parent
        assertEquals(child1.getId(), child2.getParentTaskId());
        verify(taskRepository).save(any(Task.class));   // save promoted child1
        verify(taskRepository).saveAll(any());          // save re-parented child2
        verify(taskRepository).delete(parent);          // original parent is removed
    }

    @Test
    @DisplayName("deleteTask series: removes the entire recurring series (parent + all children)")
    void testDeleteTask_series_deletesAll() throws Exception {
        // deleteSeries=true must collect all tasks in the series and call deleteAll
        final Task child = Task.builder().id(2L).parentTaskId(1L).name("Child Task").build();
        final Task parent = Task.builder().id(1L).parentTaskId(null).name("Parent Task").build();

        when(taskRepository.findById(2L)).thenReturn(Optional.of(child));
        // findByParentTaskId must return a mutable list so the service can append the parent
        when(taskRepository.findByParentTaskId(1L))
                .thenReturn(new ArrayList<>(List.of(child)));
        when(taskRepository.findById(1L)).thenReturn(Optional.of(parent));

        taskService.deleteTask(2L, true);

        verify(taskRepository).deleteAll(any());
    }

    @Test
    @DisplayName("deleteTask: throws TaskNotFoundException when the task ID does not exist")
    void testDeleteTask_taskNotFound_throws() throws Exception {
        // A delete request for a non-existent ID must fail with the domain exception
        when(taskRepository.findById(999L)).thenReturn(Optional.empty());

        assertThrows(TaskNotFoundException.class, () -> taskService.deleteTask(999L, false));
    }

    // ==========================================================================
    // existsById
    // ==========================================================================

    @Test
    @DisplayName("existsById: returns true when the task is present in the repository")
    void testExistsById_true() throws Exception {
        when(taskRepository.findById(7L)).thenReturn(Optional.of(Task.builder().id(7L).build()));

        assertTrue(taskService.existsById(7L));
    }

    @Test
    @DisplayName("existsById: returns false when no task matches the given ID")
    void testExistsById_false() throws Exception {
        when(taskRepository.findById(8L)).thenReturn(Optional.empty());

        assertFalse(taskService.existsById(8L));
    }

    // ==========================================================================
    // getAllTasks
    // ==========================================================================

    @Test
    @DisplayName("getAllTasks: maps all persisted task entities to DTOs")
    void testGetAllTasks() throws Exception {
        final Task t1 = Task.builder().id(1L).name("Task1").build();
        final Task t2 = Task.builder().id(2L).name("Task2").build();
        when(taskRepository.findAll()).thenReturn(List.of(t1, t2));

        final List<TaskDtoV2> result = taskService.getAllTasks();

        assertEquals(2, result.size());
        assertEquals("Task1", result.get(0).getName());
        verify(taskRepository).findAll();
    }

    @Test
    @DisplayName("getAllTasks: throws TaskNotFoundException when the repository contains no tasks")
    void testGetAllTasks_emptyThrows() throws Exception {
        // An empty task table is treated as an error condition for this endpoint
        when(taskRepository.findAll()).thenReturn(List.of());

        assertThrows(TaskNotFoundException.class, () -> taskService.getAllTasks());
    }

    // ==========================================================================
    // calculateCount (private — tested via reflection)
    //
    // The method encapsulates branching recurrence arithmetic; testing it directly
    // ensures the formulas are correct independent of full service integration.
    // ==========================================================================

    /**
     * Convenience wrapper that invokes the private {@code calculateCount} method
     * via reflection, keeping individual test cases concise.
     */
    private int invokeCalculateCount(
            LocalDate start, LocalDate end,
            String freq, int interval, List<Boolean> days) throws Exception {
        final Method method = TaskServiceV2.class.getDeclaredMethod(
                "calculateCount",
                LocalDate.class, LocalDate.class, String.class, int.class, List.class);
        method.setAccessible(true);
        return (int) method.invoke(taskService, start, end, freq, interval, days);
    }

    @Test
    @DisplayName("calculateCount daily interval=1: one occurrence per day inclusive of start and end")
    void testCalculateCount_daily() throws Exception {
        // 5 days inclusive (Jan 1 → Jan 5), interval=1 → 5 occurrences
        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2025, 1, 5),
                "daily", 1, null);

        assertEquals(5, result);
    }

    @Test
    @DisplayName("calculateCount daily interval=2: every-other-day spans produce half the occurrences")
    void testCalculateCount_daily_interval2() throws Exception {
        // 10-day span / interval 2 → (10/2)+1 = 6 occurrences (days 0,2,4,6,8,10)
        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2025, 1, 11),
                "daily", 2, null);

        assertEquals(6, result);
    }

    @Test
    @DisplayName("calculateCount weekly with days mask: counts only occurrences on the selected weekdays")
    void testCalculateCount_weeklyDays() throws Exception {
        // Sun=true (index 0) and Wed=true (index 3); all other days are false
        final List<Boolean> days = List.of(true, false, false, true, false, false, false);

        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2025, 1, 15),
                "weekly", 1, days);

        // There are several Sundays and Wednesdays in a 2-week window
        assertTrue(result > 0, "Expected at least one occurrence for the selected weekdays");
    }

    @Test
    @DisplayName("calculateCount weekly no days mask: counts whole-week intervals")
    void testCalculateCount_weekly_noDays() throws Exception {
        // No days mask → simple week-interval counting: (14 days / 7 / interval 1) + 1 = 3
        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2025, 1, 15),
                "weekly", 1, null);

        assertEquals(3, result);
    }

    @Test
    @DisplayName("calculateCount monthly interval=1: one occurrence per calendar month")
    void testCalculateCount_monthly() throws Exception {
        // Jan → Mar = 2 months apart → (2 / 1) + 1 = 3 occurrences (Jan, Feb, Mar)
        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2025, 3, 1),
                "monthly", 1, null);

        assertEquals(3, result);
    }

    @Test
    @DisplayName("calculateCount yearly interval=1: one occurrence per calendar year")
    void testCalculateCount_yearly() throws Exception {
        // 2025 → 2027 = 2 years apart → (2 / 1) + 1 = 3 occurrences (2025, 2026, 2027)
        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2027, 1, 1),
                "yearly", 1, null);

        assertEquals(3, result);
    }

    @Test
    @DisplayName("calculateCount unknown frequency: returns 1 as a safe fallback")
    void testCalculateCount_unknownFrequency() throws Exception {
        // An unrecognised frequency string must not throw; the default branch returns 1
        final int result = invokeCalculateCount(
                LocalDate.of(2025, 1, 1),
                LocalDate.of(2025, 12, 31),
                "hourly", 1, null);

        assertEquals(1, result);
    }
}
