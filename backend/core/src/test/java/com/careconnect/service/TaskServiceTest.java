package com.careconnect.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;

import com.careconnect.dto.TaskDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.TaskRepository;

/**
 * Unit tests for {@link TaskService}.
 *
 * <p>All repository dependencies are mocked with Mockito so the service's
 * business logic is validated in isolation — no database or Spring context
 * is required.</p>
 */
class TaskServiceTest {

    @Mock
    private TaskRepository taskRepository;

    @Mock
    private PatientRepository patientRepository;

    @InjectMocks
    private TaskService taskService;

    /**
     * Shared fixtures reused across tests.
     */
    private Patient patient;
    private Task task;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        patient = Patient.builder().id(1L).firstName("Jane").lastName("Doe").build();
        task = Task.builder().id(1L).name("Check Vitals").date("2025-06-01")
                .patient(patient).isCompleted(false).build();
    }

    // ==========================================================================
    // getTaskById
    // ==========================================================================

    @Test
    @DisplayName("getTaskById: returns the task entity when the ID exists")
    void testGetTaskById_found() throws Exception {
        // The repository finds the task; the service must return it unchanged.
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

        final Task result = taskService.getTaskById(1L);

        assertNotNull(result);
        assertEquals(1L, result.getId());
        assertEquals("Check Vitals", result.getName());
        verify(taskRepository).findById(1L);
    }

    @Test
    @DisplayName("getTaskById: throws AppException(NOT_FOUND) when the ID does not exist")
    void testGetTaskById_notFound() throws Exception {
        // A missing task must surface as a 404 AppException, not a null return.
        when(taskRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> taskService.getTaskById(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(taskRepository).findById(99L);
    }

    // ==========================================================================
    // getTasksByPatient
    // ==========================================================================

    @Test
    @DisplayName("getTasksByPatient: returns the full list when tasks exist for the patient")
    void testGetTasksByPatient_returnsList() throws Exception {
        // Both entities must be present in the returned list in order.
        final Task t2 = Task.builder().id(2L).name("Take Medication").patient(patient).build();
        when(taskRepository.findByPatientId(1L)).thenReturn(Optional.of(List.of(task, t2)));

        final List<Task> result = taskService.getTasksByPatient(1L);

        assertEquals(2, result.size());
        assertEquals("Check Vitals", result.get(0).getName());
        assertEquals("Take Medication", result.get(1).getName());
        verify(taskRepository).findByPatientId(1L);
    }

    @Test
    @DisplayName("getTasksByPatient: returns an empty (non-null) list when no tasks exist")
    void testGetTasksByPatient_noTasks_returnsEmptyList() throws Exception {
        // Optional.empty() from the repository must produce an empty list, not throw.
        when(taskRepository.findByPatientId(99L)).thenReturn(Optional.empty());

        final List<Task> result = taskService.getTasksByPatient(99L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getTasksByPatient: returns an empty list when the repository wraps an empty list")
    void testGetTasksByPatient_emptyList_returnsEmptyList() throws Exception {
        // An Optional containing an empty list must also produce an empty result.
        when(taskRepository.findByPatientId(2L)).thenReturn(Optional.of(new ArrayList<>()));

        final List<Task> result = taskService.getTasksByPatient(2L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    // ==========================================================================
    // createTask
    // ==========================================================================

    @Test
    @DisplayName("createTask: saves new task and returns persisted entity with all mapped fields")
    void testCreateTask_happyPath() throws Exception {
        // Given a valid patient and a fully-populated DTO, every field must
        // be transferred to the saved entity and the persisted task returned.
        final TaskDto dto = TaskDto.builder()
                .name("Daily Walk")
                .description("30-minute walk around the park")
                .date("2025-07-01")
                .timeOfDay("08:00")
                .isCompleted(false)
                .frequency("daily")
                .interval(1)
                .count(5)
                .daysOfWeek("MON,WED,FRI")
                .taskType("Exercise")
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
            final Task t = inv.getArgument(0);
            t.setId(10L);
            return t;
        });

        final Task result = taskService.createTask(1L, dto);

        assertNotNull(result);
        assertEquals(10L, result.getId());
        assertEquals("Daily Walk", result.getName());
        assertEquals("2025-07-01", result.getDate());
        assertEquals("08:00", result.getTimeOfDay());
        assertFalse(result.isCompleted());
        assertEquals("daily", result.getFrequency());
        assertEquals(1, result.getTaskInterval());
        assertEquals(5, result.getDoCount());
        assertEquals("MON,WED,FRI", result.getDaysOfWeek());
        assertEquals("Exercise", result.getTaskType());
        assertEquals(patient, result.getPatient());
        verify(patientRepository).findById(1L);
        verify(taskRepository).save(any(Task.class));
    }

    @Test
    @DisplayName("createTask: throws AppException(NOT_FOUND) when the patient does not exist")
    void testCreateTask_patientNotFound_throws() throws Exception {
        // No task may be created without a valid owning patient.
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final TaskDto dto = TaskDto.builder()
                .name("Checkup").date("2025-01-01").isCompleted(false).build();

        final AppException ex = assertThrows(AppException.class,
                () -> taskService.createTask(99L, dto));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(taskRepository, never()).save(any());
    }

    @Test
    @DisplayName("createTask: links the correct patient entity to the new task")
    void testCreateTask_correctPatientLinked() throws Exception {
        // The task's patient relationship must reference the exact entity
        // returned by the patient repository lookup.
        final TaskDto dto = TaskDto.builder()
                .name("Lab Test").date("2025-08-01").isCompleted(false).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        final Task result = taskService.createTask(1L, dto);

        assertSame(patient, result.getPatient());
    }

    // ==========================================================================
    // updateTask
    // ==========================================================================

    @Test
    @DisplayName("updateTask: overwrites all fields on the existing entity and saves")
    void testUpdateTask_updatesAllFields() throws Exception {
        // Every field in the DTO must replace the corresponding value on the
        // stored task; the service must delegate to save and return the result.
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        final TaskDto dto = TaskDto.builder()
                .name("Updated Name")
                .description("Updated description")
                .date("2025-09-01")
                .timeOfDay("10:00")
                .isCompleted(true)
                .frequency("weekly")
                .interval(2)
                .count(4)
                .daysOfWeek("TUE,THU")
                .taskType("Appointment")
                .build();

        final Task result = taskService.updateTask(1L, dto);

        assertEquals("Updated Name", result.getName());
        assertEquals("Updated description", result.getDescription());
        assertEquals("2025-09-01", result.getDate());
        assertEquals("10:00", result.getTimeOfDay());
        assertTrue(result.isCompleted());
        assertEquals("weekly", result.getFrequency());
        assertEquals(2, result.getTaskInterval());
        assertEquals(4, result.getDoCount());
        assertEquals("TUE,THU", result.getDaysOfWeek());
        assertEquals("Appointment", result.getTaskType());
        verify(taskRepository).save(task);
    }

    @Test
    @DisplayName("updateTask: throws AppException(NOT_FOUND) when the task does not exist")
    void testUpdateTask_taskNotFound_throws() throws Exception {
        // getTaskById is called internally; a missing task must propagate
        // as a 404 AppException before any save is attempted.
        when(taskRepository.findById(99L)).thenReturn(Optional.empty());

        final TaskDto dto = TaskDto.builder()
                .name("Any Name").date("2025-01-01").isCompleted(false).build();

        final AppException ex = assertThrows(AppException.class,
                () -> taskService.updateTask(99L, dto));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(taskRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateTask: returns the saved entity (not just the modified local object)")
    void testUpdateTask_returnsSavedEntity() throws Exception {
        // The save call may return a different instance (e.g., with DB-generated
        // fields); the service must return what the repository gives back.
        final Task savedTask = Task.builder().id(1L).name("Saved Name").patient(patient).build();

        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenReturn(savedTask);

        final TaskDto dto = TaskDto.builder()
                .name("Saved Name").date("2025-01-01").isCompleted(false).build();

        final Task result = taskService.updateTask(1L, dto);

        assertSame(savedTask, result);
    }

    // ==========================================================================
    // deleteTask
    // ==========================================================================

    @Test
    @DisplayName("deleteTask: deletes the task and returns true when it exists")
    void testDeleteTask_exists_returnsTrue() throws Exception {
        // The happy path: the task is found, deleted, and the method returns true.
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

        final boolean result = taskService.deleteTask(1L);

        assertTrue(result);
        verify(taskRepository).delete(task);
    }

    @Test
    @DisplayName("deleteTask: throws AppException(NOT_FOUND) when the task does not exist")
    void testDeleteTask_notFound_throws() throws Exception {
        // A delete on a non-existent task must fail before calling delete().
        when(taskRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> taskService.deleteTask(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(taskRepository, never()).delete(any(Task.class));
    }

    @Test
    @DisplayName("deleteTask: delegates to repository.delete with the exact task entity")
    void testDeleteTask_passesCorrectEntityToRepository() throws Exception {
        // The correct Task object (not just by ID) must be passed to delete().
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

        taskService.deleteTask(1L);

        verify(taskRepository).delete(task);
    }

    // ==========================================================================
    // existsById
    // ==========================================================================

    @Test
    @DisplayName("existsById: returns true when the task is present in the repository")
    void testExistsById_true() throws Exception {
        // findById returning a value must cause existsById to return true.
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

        assertTrue(taskService.existsById(1L));
    }

    @Test
    @DisplayName("existsById: returns false when no task matches the given ID")
    void testExistsById_false() throws Exception {
        // findById returning empty must cause existsById to return false.
        when(taskRepository.findById(99L)).thenReturn(Optional.empty());

        assertFalse(taskService.existsById(99L));
    }

    // ==========================================================================
    // getAllTasks
    // ==========================================================================

    @Test
    @DisplayName("getAllTasks: returns all persisted task entities when tasks exist")
    void testGetAllTasks_returnsList() throws Exception {
        // The full list from the repository must be returned without modification.
        final Task t2 = Task.builder().id(2L).name("Take Medication").patient(patient).build();
        when(taskRepository.findAll()).thenReturn(List.of(task, t2));

        final List<Task> result = taskService.getAllTasks();

        assertEquals(2, result.size());
        assertEquals("Check Vitals", result.get(0).getName());
        assertEquals("Take Medication", result.get(1).getName());
        verify(taskRepository).findAll();
    }

    @Test
    @DisplayName("getAllTasks: throws AppException(NOT_FOUND) when the repository is empty")
    void testGetAllTasks_emptyRepository_throws() throws Exception {
        // An empty task table is treated as a not-found error condition.
        when(taskRepository.findAll()).thenReturn(List.of());

        final AppException ex = assertThrows(AppException.class,
                () -> taskService.getAllTasks());

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
    }

    @Test
    @DisplayName("getAllTasks: returns a single-item list when exactly one task exists")
    void testGetAllTasks_singleTask() throws Exception {
        // Edge case: exactly one task must not trigger the empty-check exception.
        when(taskRepository.findAll()).thenReturn(List.of(task));

        final List<Task> result = taskService.getAllTasks();

        assertEquals(1, result.size());
        assertEquals("Check Vitals", result.get(0).getName());
    }
}
