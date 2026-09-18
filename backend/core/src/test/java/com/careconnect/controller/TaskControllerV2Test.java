package com.careconnect.controller;

import static org.hamcrest.Matchers.is;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.careconnect.controller.v2.TaskControllerV2;
import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.v2.TaskServiceV2;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Unit tests for {@link TaskControllerV2}, covering the HTTP layer of all
 * task-management endpoints exposed under {@code /v2/api/tasks}.
 *
 * <p><b>Why @WebMvcTest + MockMvc?</b><br>
 * {@code @WebMvcTest} spins up only the Spring MVC slice (controllers, filters,
 * argument resolvers) without loading a full application context or a real
 * database.  This keeps the tests fast and focused: they verify that the
 * controller routes requests to the correct service methods, applies the right
 * HTTP status codes, and serialises/deserialises JSON properly — without caring
 * about the actual business logic inside the services.
 *
 * <p>All service collaborators are replaced with Mockito mocks via
 * {@code @MockBean} so that each test exercises only the controller layer in
 * isolation.  Security filters are disabled with
 * {@code @AutoConfigureMockMvc(addFilters = false)} so that tests can focus
 * on request-routing and response-shaping behaviour.
 */
@WebMvcTest(TaskControllerV2.class)
@AutoConfigureMockMvc(addFilters = false)
class TaskControllerV2Test {

    @Autowired
    private MockMvc mockMvc;

    // --- Mocked collaborators ---
    // TaskServiceV2 is the sole service dependency of TaskControllerV2; it is
    // replaced with a Mockito stub so the controller can be exercised without
    // a real database or business-logic layer.

    @MockitoBean
    private TaskServiceV2 taskService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    @Autowired
    private ObjectMapper objectMapper;

    // --- Test fixture ---
    // sampleTask is a reusable, pre-built DTO used across multiple tests to
    // avoid repeating boilerplate task construction in every test method.

    private TaskDtoV2 sampleTask;

    @BeforeEach
    void setup() throws Exception {
        sampleTask = TaskDtoV2.builder()
                .id(1L)
                .name("Check Blood Pressure")
                .description("Daily vitals check")
                .isCompleted(false)
                .taskType("Health")
                .build();
    }

    // --------------------------------------------------------------------------
    // GET /v2/api/tasks
    // --------------------------------------------------------------------------

    /**
     * Verifies that GET /v2/api/tasks returns HTTP 200 and the full list of
     * tasks when the service returns a non-empty result.
     *
     * <p>{@link TaskServiceV2#getAllTasks} is stubbed to return a single-element
     * list containing {@code sampleTask}.  The test then asserts the status code
     * and spot-checks the first element's {@code name} and {@code id} fields to
     * confirm correct JSON serialisation.
     */
    @Test
    @DisplayName("GET /v2/api/tasks should return all tasks")
    void testGetAllTasks() throws Exception {
        Mockito.when(taskService.getAllTasks()).thenReturn(List.of(sampleTask));

        mockMvc.perform(get("/v2/api/tasks"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name", is("Check Blood Pressure")))
                .andExpect(jsonPath("$[0].id", is(1)));

        Mockito.verify(taskService).getAllTasks();
    }

    // --------------------------------------------------------------------------
    // GET /v2/api/tasks/{id}
    // --------------------------------------------------------------------------

    /**
     * Verifies that GET /v2/api/tasks/{id} returns HTTP 200 and the matching
     * task DTO when the requested task exists.
     *
     * <p>{@link TaskServiceV2#getTaskDtoById} is stubbed with ID {@code 1L} to
     * return {@code sampleTask}.  The test asserts both the status and the JSON
     * fields {@code $.name} and {@code $.id}, confirming that the controller
     * correctly passes the path variable to the service and relays the response.
     */
    @Test
    @DisplayName("GET /v2/api/tasks/{id} should return a single task")
    void testGetTaskById() throws Exception {
        Mockito.when(taskService.getTaskDtoById(1L)).thenReturn(sampleTask);

        mockMvc.perform(get("/v2/api/tasks/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name", is("Check Blood Pressure")))
                .andExpect(jsonPath("$.id", is(1)));

        Mockito.verify(taskService).getTaskDtoById(1L);
    }

    // --------------------------------------------------------------------------
    // GET /v2/api/tasks/patient/{patientId}
    // --------------------------------------------------------------------------

    /**
     * Verifies that GET /v2/api/tasks/patient/{patientId} returns HTTP 200 and
     * the tasks belonging to the specified patient.
     *
     * <p>{@link TaskServiceV2#getTasksByPatient} is stubbed with patient ID
     * {@code 5L} to return a list containing {@code sampleTask}.  The test
     * confirms that the controller extracts the path variable correctly and
     * that the response body includes the expected task.
     */
    @Test
    @DisplayName("GET /v2/api/tasks/patient/{patientId} should return patient tasks")
    void testGetTasksByPatient() throws Exception {
        Mockito.when(taskService.getTasksByPatient(5L)).thenReturn(List.of(sampleTask));

        mockMvc.perform(get("/v2/api/tasks/patient/5"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name", is("Check Blood Pressure")));

        Mockito.verify(taskService).getTasksByPatient(5L);
    }

    // --------------------------------------------------------------------------
    // POST /v2/api/tasks/patient/{patientId}
    // --------------------------------------------------------------------------

    /**
     * Verifies that POST /v2/api/tasks/patient/{patientId} returns HTTP 200 and
     * the newly created task DTO when a valid request body is provided.
     *
     * <p>{@link TaskServiceV2#createTask} is stubbed to return {@code sampleTask}
     * for patient ID {@code 5L} and any {@link TaskDtoV2} request body.  The
     * test serialises {@code sampleTask} as the request payload and asserts that
     * the response contains the correct task name.
     */
    @Test
    @DisplayName("POST /v2/api/tasks/patient/{patientId} should create a task")
    void testCreateTask() throws Exception {
        Mockito.when(taskService.createTask(eq(5L), any(TaskDtoV2.class))).thenReturn(sampleTask);

        mockMvc.perform(post("/v2/api/tasks/patient/5")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleTask)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name", is("Check Blood Pressure")));

        Mockito.verify(taskService).createTask(eq(5L), any(TaskDtoV2.class));
    }

    // --------------------------------------------------------------------------
    // PUT /v2/api/tasks/{id}
    // --------------------------------------------------------------------------

    /**
     * Verifies that PUT /v2/api/tasks/{id} returns HTTP 200 and the updated
     * task DTO when a valid updated body is provided.
     *
     * <p>An {@code updated} DTO is built from {@code sampleTask} with
     * {@code isCompleted} flipped to {@code true}.  {@link TaskServiceV2#updateTask}
     * is stubbed to return this updated DTO.  The test asserts that the response
     * reflects the new completion status ({@code $.completed}), confirming that
     * the controller serialises the service's return value correctly.
     */
    @Test
    @DisplayName("PUT /v2/api/tasks/{id} should update a task")
    void testUpdateTask() throws Exception {
        TaskDtoV2 updated = TaskDtoV2.builder()
                .id(sampleTask.getId())
                .name(sampleTask.getName())
                .description(sampleTask.getDescription())
                .isCompleted(true)
                .taskType(sampleTask.getTaskType())
                .build();

        Mockito.when(taskService.updateTask(eq(1L), any(TaskDtoV2.class))).thenReturn(updated);

        mockMvc.perform(put("/v2/api/tasks/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updated)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.completed", is(true)));

        Mockito.verify(taskService).updateTask(eq(1L), any(TaskDtoV2.class));
    }

    // --------------------------------------------------------------------------
    // PUT /v2/api/tasks/{id}/complete
    // --------------------------------------------------------------------------

    /**
     * Verifies that PUT /v2/api/tasks/{id}/complete returns HTTP 200 and the
     * updated task DTO after toggling the completion status.
     *
     * <p>The request body carries {@code {"isComplete": true}}.
     * {@link TaskServiceV2#updateCompletionStatus} is stubbed to return a DTO
     * with {@code isCompleted=true}.  The test asserts the {@code $.completed}
     * field in the response, confirming that the controller correctly reads the
     * boolean from the body and delegates to the service.
     */
    @Test
    @DisplayName("PUT /v2/api/tasks/{id}/complete should update completion status")
    void testUpdateTaskCompletion() throws Exception {
        TaskDtoV2 updated = TaskDtoV2.builder()
                .id(sampleTask.getId())
                .name(sampleTask.getName())
                .description(sampleTask.getDescription())
                .isCompleted(true)
                .taskType(sampleTask.getTaskType())
                .build();

        Mockito.when(taskService.updateCompletionStatus(1L, true)).thenReturn(updated);

        mockMvc.perform(put("/v2/api/tasks/1/complete")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("isComplete", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.completed", is(true)));

        Mockito.verify(taskService).updateCompletionStatus(1L, true);
    }

    // --------------------------------------------------------------------------
    // DELETE /v2/api/tasks/{id}
    // --------------------------------------------------------------------------

    /**
     * Verifies that DELETE /v2/api/tasks/{id} returns HTTP 204 No Content and
     * delegates to {@link TaskServiceV2#deleteTask} with the correct arguments.
     *
     * <p>No service stub is required because the controller only needs to call
     * {@code deleteTask} and return 204 — the default Mockito void behaviour is
     * sufficient.  The test confirms the status code and uses
     * {@link Mockito#verify} to assert that the service received the correct
     * task ID and {@code deleteSeries} flag.
     */
    @Test
    @DisplayName("DELETE /v2/api/tasks/{id} should call service and return 204")
    void testDeleteTask() throws Exception {
        mockMvc.perform(delete("/v2/api/tasks/1")
                        .param("deleteSeries", "false"))
                .andExpect(status().isNoContent());

        Mockito.verify(taskService).deleteTask(1L, false);
    }
}
