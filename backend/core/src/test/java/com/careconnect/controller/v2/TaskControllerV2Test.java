package com.careconnect.controller.v2;

import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.v2.TaskServiceV2;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TaskControllerV2Test {

    @Mock
    private TaskServiceV2 taskService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private TaskControllerV2 controller;

    // ─── getAllTasks ───────────────────────────────────────────────────────────

    @Test
    void getAllTasks_returnsOkWithList() throws Exception {
        final TaskDtoV2 task = TaskDtoV2.builder().id(1L).name("Med Check").date("2026-03-01").isCompleted(false).build();
        when(taskService.getAllTasks()).thenReturn(List.of(task));

        final ResponseEntity<List<TaskDtoV2>> response = controller.getAllTasks();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getName()).isEqualTo("Med Check");
        verify(taskService).getAllTasks();
    }

    @Test
    void getAllTasks_emptyList_returnsOkWithEmptyBody() throws Exception {
        when(taskService.getAllTasks()).thenReturn(List.of());

        final ResponseEntity<List<TaskDtoV2>> response = controller.getAllTasks();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    // ─── getTaskById ──────────────────────────────────────────────────────────

    @Test
    void getTaskById_returnsOkWithTask() throws Exception {
        final TaskDtoV2 task = TaskDtoV2.builder().id(42L).name("Blood Draw").date("2026-03-10").isCompleted(false).build();
        when(taskService.getTaskDtoById(42L)).thenReturn(task);

        final ResponseEntity<TaskDtoV2> response = controller.getTaskById(42L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getId()).isEqualTo(42L);
        assertThat(response.getBody().getName()).isEqualTo("Blood Draw");
        verify(taskService).getTaskDtoById(42L);
    }

    // ─── getTasksByPatient ────────────────────────────────────────────────────

    @Test
    void getTasksByPatient_returnsOkWithList() throws Exception {
        final TaskDtoV2 t1 = TaskDtoV2.builder().id(1L).name("Task A").date("2026-03-01").isCompleted(false).build();
        final TaskDtoV2 t2 = TaskDtoV2.builder().id(2L).name("Task B").date("2026-03-02").isCompleted(true).build();
        when(taskService.getTasksByPatient(10L)).thenReturn(List.of(t1, t2));

        final ResponseEntity<List<TaskDtoV2>> response = controller.getTasksByPatient(10L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(2);
        verify(taskService).getTasksByPatient(10L);
    }

    @Test
    void getTasksByPatient_noTasks_returnsOkWithEmptyList() throws Exception {
        when(taskService.getTasksByPatient(99L)).thenReturn(List.of());

        final ResponseEntity<List<TaskDtoV2>> response = controller.getTasksByPatient(99L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    // ─── createTask ───────────────────────────────────────────────────────────

    @Test
    void createTask_returnsOkWithCreatedTask() throws Exception {
        final TaskDtoV2 requestDto = TaskDtoV2.builder().name("Exercise").date("2026-04-01").isCompleted(false).build();
        final TaskDtoV2 savedDto = TaskDtoV2.builder().id(5L).name("Exercise").date("2026-04-01").isCompleted(false).build();
        when(taskService.createTask(10L, requestDto)).thenReturn(savedDto);

        final ResponseEntity<TaskDtoV2> response = controller.createTask(10L, requestDto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getId()).isEqualTo(5L);
        verify(taskService).createTask(10L, requestDto);
    }

    // ─── updateTask ───────────────────────────────────────────────────────────

    @Test
    void updateTask_returnsOkWithUpdatedTask() throws Exception {
        final TaskDtoV2 requestDto = TaskDtoV2.builder().name("Updated Task").date("2026-04-05").isCompleted(false).build();
        final TaskDtoV2 updatedDto = TaskDtoV2.builder().id(7L).name("Updated Task").date("2026-04-05").isCompleted(false).build();
        when(taskService.updateTask(7L, requestDto)).thenReturn(updatedDto);

        final ResponseEntity<TaskDtoV2> response = controller.updateTask(7L, requestDto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getName()).isEqualTo("Updated Task");
        verify(taskService).updateTask(7L, requestDto);
    }

    // ─── updateTaskCompletion ─────────────────────────────────────────────────

    @Test
    void updateTaskCompletion_withIsCompleteTrue_marksTaskComplete() throws Exception {
        final TaskDtoV2 updated = TaskDtoV2.builder().id(3L).name("Medication").date("2026-03-15").isCompleted(true).build();
        when(taskService.updateCompletionStatus(3L, true)).thenReturn(updated);

        final ResponseEntity<TaskDtoV2> response = controller.updateTaskCompletion(3L, Map.of("isComplete", true));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().isCompleted()).isTrue();
        verify(taskService).updateCompletionStatus(3L, true);
    }

    @Test
    void updateTaskCompletion_withIsCompleteFalse_marksTaskIncomplete() throws Exception {
        final TaskDtoV2 updated = TaskDtoV2.builder().id(3L).name("Medication").date("2026-03-15").isCompleted(false).build();
        when(taskService.updateCompletionStatus(3L, false)).thenReturn(updated);

        final ResponseEntity<TaskDtoV2> response = controller.updateTaskCompletion(3L, Map.of("isComplete", false));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().isCompleted()).isFalse();
        verify(taskService).updateCompletionStatus(3L, false);
    }

    @Test
    void updateTaskCompletion_withMissingKey_defaultsToFalse() throws Exception {
        final TaskDtoV2 updated = TaskDtoV2.builder().id(4L).name("Checkup").date("2026-03-20").isCompleted(false).build();
        when(taskService.updateCompletionStatus(4L, false)).thenReturn(updated);

        final ResponseEntity<TaskDtoV2> response = controller.updateTaskCompletion(4L, Map.of());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(taskService).updateCompletionStatus(4L, false);
    }

    // ─── deleteTask ───────────────────────────────────────────────────────────

    @Test
    void deleteTask_singleTask_returnsNoContent() throws Exception {
        doNothing().when(taskService).deleteTask(8L, false);

        final ResponseEntity<Void> response = controller.deleteTask(8L, false);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        assertThat(response.getBody()).isNull();
        verify(taskService).deleteTask(8L, false);
    }

    @Test
    void deleteTask_entireSeries_returnsNoContent() throws Exception {
        doNothing().when(taskService).deleteTask(8L, true);

        final ResponseEntity<Void> response = controller.deleteTask(8L, true);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        assertThat(response.getBody()).isNull();
        verify(taskService).deleteTask(8L, true);
    }
}
