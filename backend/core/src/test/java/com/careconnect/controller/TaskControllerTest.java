package com.careconnect.controller;

import com.careconnect.dto.TaskDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Task;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.TaskService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.http.HttpStatus;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(TaskController.class)
@DisplayName("TaskController Tests")
class TaskControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private TaskService taskService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    private Task sampleTask;
    private TaskDto sampleTaskDto;

    @BeforeEach
    void setUp() throws Exception {
        sampleTask = Task.builder()
                .id(1L)
                .name("Check Blood Pressure")
                .description("Daily blood pressure check")
                .date("2026-02-20")
                .timeOfDay("08:00 AM")
                .isCompleted(false)
                .frequency("DAILY")
                .taskInterval(1)
                .doCount(7)
                .daysOfWeek("MON,TUE,WED,THU,FRI,SAT,SUN")
                .taskType("Health")
                .build();

        sampleTaskDto = TaskDto.builder()
                .name("Check Blood Pressure")
                .description("Daily blood pressure check")
                .date("2026-02-20")
                .timeOfDay("08:00 AM")
                .isCompleted(false)
                .frequency("DAILY")
                .interval(1)
                .count(7)
                .daysOfWeek("MON,TUE,WED,THU,FRI,SAT,SUN")
                .taskType("Health")
                .build();
    }

    @Nested
    @DisplayName("GET /tasks")
    class GetAllTasks {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns all tasks")
        void returnsAllTasks() throws Exception {
            // Arrange
            when(taskService.getAllTasks()).thenReturn(List.of(sampleTask));

            // Act + Assert
            mockMvc.perform(get("/v3/api/tasks"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(1))
                    .andExpect(jsonPath("$[0].name").value("Check Blood Pressure"));

            // Assert
            verify(taskService).getAllTasks();
        }
    }

    @Nested
    @DisplayName("GET /tasks/{id}")
    class GetTaskById {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 200 when task exists")
        void returns200WhenTaskExists() throws Exception {
            // Arrange
            when(taskService.getTaskById(1L)).thenReturn(sampleTask);

            // Act + Assert
            mockMvc.perform(get("/v3/api/tasks/1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.name").value("Check Blood Pressure"));

            // Assert
            verify(taskService).getTaskById(1L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 404 when task does not exist")
        void returns404WhenTaskMissing() throws Exception {
            // Match the real service: missing tasks throw a 404 exception.
            when(taskService.getTaskById(999L))
                .thenThrow(new AppException(HttpStatus.NOT_FOUND, "Task not found"));

            mockMvc.perform(get("/v3/api/tasks/999")).andExpect(status().isNotFound());

            verify(taskService).getTaskById(999L);

            // Lookup failed, so task authorization must never run.
            verify(authorizationService, never()).requireTaskAccess(any(), any());
        }
    }

    @Nested
    @DisplayName("GET /tasks/patient/{patientId}")
    class GetTasksByPatient {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns tasks for patient")
        void returnsTasksForPatient() throws Exception {
            // Arrange
            when(taskService.getTasksByPatient(10L)).thenReturn(List.of(sampleTask));

            // Act + Assert
            mockMvc.perform(get("/v3/api/tasks/patient/10"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(1))
                    .andExpect(jsonPath("$[0].name").value("Check Blood Pressure"));

            // Assert
            verify(taskService).getTasksByPatient(10L);
        }
    }

    @Nested
    @DisplayName("POST /tasks/patient/{patientId}")
    class CreateTask {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Creates task for patient")
        void createsTaskForPatient() throws Exception {
            // Arrange
            when(taskService.createTask(eq(10L), any(TaskDto.class))).thenReturn(sampleTask);

            // Act + Assert
            mockMvc.perform(post("/v3/api/tasks/patient/10")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleTaskDto)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.name").value("Check Blood Pressure"));

            // Assert
            verify(taskService).createTask(eq(10L), any(TaskDto.class));
        }
    }

    @Nested
    @DisplayName("PUT /tasks/{id}")
    class UpdateTask {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns updated task when id exists")
        void returnsUpdatedTaskWhenFound() throws Exception {
            // Arrange
            final Task updatedTask = Task.builder()
                    .id(1L)
                    .name("Updated Task Name")
                    .description("Updated Description")
                    .date("2026-02-21")
                    .isCompleted(true)
                    .taskType("Health")
                    .build();
            when(taskService.updateTask(eq(1L), any(TaskDto.class))).thenReturn(updatedTask);

            // Act + Assert
            mockMvc.perform(put("/v3/api/tasks/1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleTaskDto)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.name").value("Updated Task Name"));

            // Assert
            verify(taskService).updateTask(eq(1L), any(TaskDto.class));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 404 when update target does not exist")
        void returns404WhenUpdateTargetMissing() throws Exception {
            // Arrange
            when(taskService.updateTask(eq(999L), any(TaskDto.class))).thenReturn(null);

            // Act + Assert
            mockMvc.perform(put("/v3/api/tasks/999")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleTaskDto)))
                    .andExpect(status().isNotFound());

            // Assert
            verify(taskService).updateTask(eq(999L), any(TaskDto.class));
        }
    }

    @Nested
    @DisplayName("DELETE /tasks/{id}")
    class DeleteTask {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 204 when delete succeeds")
        void returns204WhenDeleteSucceeds() throws Exception {
            // Arrange
            when(taskService.deleteTask(1L)).thenReturn(true);

            // Act + Assert
            mockMvc.perform(delete("/v3/api/tasks/1").with(csrf()))
                    .andExpect(status().isNoContent());

            // Assert
            verify(taskService).deleteTask(1L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 404 when delete target does not exist")
        void returns404WhenDeleteTargetMissing() throws Exception {
            // Arrange
            when(taskService.deleteTask(999L)).thenReturn(false);

            // Act + Assert
            mockMvc.perform(delete("/v3/api/tasks/999").with(csrf()))
                    .andExpect(status().isNotFound());

            // Assert
            verify(taskService).deleteTask(999L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 403 and deletes nothing when the caller cannot access the task's patient")
        void returns403WhenCallerCannotAccessTask() throws Exception {
            // Arrange: an unlinked caregiver targets another patient's task
            when(taskService.getTaskById(1L)).thenReturn(sampleTask);
            doThrow(new UnauthorizedException("Caregiver is not assigned to patient 5"))
                    .when(authorizationService).requireTaskAccess(any(), eq(sampleTask));

            // Act + Assert
            mockMvc.perform(delete("/v3/api/tasks/1").with(csrf()))
                    .andExpect(status().isForbidden());

            // Assert
            verify(taskService, never()).deleteTask(anyLong());
        }
    }

    @Nested
    @DisplayName("Family members are read-only")
    class ReadOnlyFamilyMember {

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("POST returns 403 and creates nothing")
        void createReturns403() throws Exception {
            // Arrange: the patient check passes, the write check refuses
            doThrow(new UnauthorizedException("read-only")).when(authorizationService).requireWriteAccess(any());

            // Act + Assert
            mockMvc.perform(post("/v3/api/tasks/patient/10").with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleTaskDto)))
                    .andExpect(status().isForbidden());
            verify(taskService, never()).createTask(anyLong(), any(TaskDto.class));
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("PUT returns 403 and changes nothing")
        void updateReturns403() throws Exception {
            when(taskService.getTaskById(1L)).thenReturn(sampleTask);
            doThrow(new UnauthorizedException("read-only")).when(authorizationService).requireWriteAccess(any());

            mockMvc.perform(put("/v3/api/tasks/1").with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleTaskDto)))
                    .andExpect(status().isForbidden());
            verify(taskService, never()).updateTask(anyLong(), any(TaskDto.class));
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("DELETE returns 403 and deletes nothing")
        void deleteReturns403() throws Exception {
            when(taskService.getTaskById(1L)).thenReturn(sampleTask);
            doThrow(new UnauthorizedException("read-only")).when(authorizationService).requireWriteAccess(any());

            mockMvc.perform(delete("/v3/api/tasks/1").with(csrf()))
                    .andExpect(status().isForbidden());
            verify(taskService, never()).deleteTask(anyLong());
        }
    }
}
