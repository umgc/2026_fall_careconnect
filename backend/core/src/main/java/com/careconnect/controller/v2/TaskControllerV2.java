package com.careconnect.controller.v2;

import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.exception.TaskNotFoundException;
import com.careconnect.service.v2.TaskServiceV2;

/**
 * REST controller for managing tasks (API v2).
 *
 * <p>
 * Exposes endpoints for creating, retrieving, updating,
 * and deleting tasks. All endpoints return {@link TaskDtoV2}
 * objects instead of entities, ensuring a clean separation
 * between persistence and API layers.
 * </p>
 *
 * <p>
 * Base path: {@code /v2/api/tasks}
 * </p>
 *
 * <p>
 * Supported operations:
 * <ul>
 * <li>Get all tasks</li>
 * <li>Get task by ID</li>
 * <li>Get tasks for a patient</li>
 * <li>Create a new task for a patient</li>
 * <li>Update an existing task</li>
 * <li>Delete a task (single or entire series)</li>
 * </ul>
 * </p>
 */
@RestController
@RequestMapping("/v2/api/tasks")
public class TaskControllerV2 {

    private final TaskServiceV2 taskService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    /**
     * Constructs a new {@code TaskControllerV2} with the given service.
     *
     * @param taskService          service layer handling business logic for tasks
     * @param securityUtil         utility for resolving the current user
     * @param authorizationService service for enforcing RBAC
     */
    public TaskControllerV2(TaskServiceV2 taskService, SecurityUtil securityUtil, AuthorizationService authorizationService) {
        this.taskService = taskService;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
    }

    /**
     * Retrieves all tasks in the system.
     *
     * <p>
     * Endpoint: {@code GET /v2/api/tasks}
     * </p>
     *
     * @return list of all {@link TaskDtoV2} objects
     */
    @GetMapping
    public ResponseEntity<List<TaskDtoV2>> getAllTasks() {
        return ResponseEntity.ok(taskService.getAllTasks());
    }

    /**
     * Retrieves a task by its unique identifier.
     *
     * <p>
     * Endpoint: {@code GET /v2/api/tasks/{id}}
     * </p>
     *
     * @param id task ID
     * @return the matching {@link TaskDtoV2}, or {@code 404 Not Found} if none
     * exists
     */
    @GetMapping("/{id}")
    public ResponseEntity<TaskDtoV2> getTaskById(@PathVariable Long id) {
        return ResponseEntity.ok(taskService.getTaskDtoById(id));
    }

    /**
     * Retrieves all tasks assigned to a specific patient.
     *
     * <p>
     * Endpoint: {@code GET /v2/api/tasks/patient/{patientId}}
     * </p>
     *
     * @param patientId the patient’s ID
     * @return list of {@link TaskDtoV2} objects for the patient
     */
    @GetMapping("/patient/{patientId}")
    public ResponseEntity<List<TaskDtoV2>> getTasksByPatient(@PathVariable Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        return ResponseEntity.ok(taskService.getTasksByPatient(patientId));
    }

    /**
     * Creates a new task for a specific patient.
     *
     * <p>
     * Endpoint: {@code POST /v2/api/tasks/patient/{patientId}}
     * </p>
     *
     * @param patientId the patient’s ID
     * @param task      the task details (DTO)
     * @return the created {@link TaskDtoV2}
     */
    @PostMapping("/patient/{patientId}")
    public ResponseEntity<TaskDtoV2> createTask(
            @PathVariable Long patientId,
            @RequestBody TaskDtoV2 task) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        return ResponseEntity.ok(taskService.createTask(patientId, task));
    }

    /**
     * Updates an existing task by its ID.
     *
     * <p>
     * Endpoint: {@code PUT /v2/api/tasks/{id}}
     * </p>
     *
     * @param id   task ID
     * @param task updated task details (DTO)
     * @return the updated {@link TaskDtoV2}
     */
    @PutMapping("/{id}")
    public ResponseEntity<TaskDtoV2> updateTask(
            @PathVariable Long id,
            @RequestBody TaskDtoV2 task) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(taskService.updateTask(id, task));
    }

    /**
     * Updates the completion status of a task.
     *
     * <p>
     * This endpoint is called when a user marks a task as complete or incomplete
     * from the front-end interface. It accepts a simple JSON body containing
     * {@code isComplete: true/false}, updates the corresponding task record, and
     * returns the updated {@link TaskDtoV2}.
     * </p>
     *
     * <p>
     * Example request body:
     *
     * <pre>
     * {
     *   "isComplete": true
     * }
     * </pre>
     *
     * <p>
     * Example cURL:
     *
     * <pre>
     * curl -X PUT "http://localhost:8080/v2/api/tasks/42/complete" \
     *      -H "Content-Type: application/json" \
     *      -H "Authorization: Bearer &lt;token&gt;" \
     *      -d '{"isComplete": true}'
     * </pre>
     *
     * @param id   the unique ID of the task to update
     * @param body a JSON map containing the {@code isComplete} boolean field
     * @return the updated {@link TaskDtoV2} with the new completion state
     * @throws TaskNotFoundException if no task exists with the specified ID
     */
    @PutMapping("/{id}/complete")
    public ResponseEntity<TaskDtoV2> updateTaskCompletion(
            @PathVariable Long id,
            @RequestBody Map<String, Boolean> body) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        boolean isComplete = body.getOrDefault("isComplete", false);
        TaskDtoV2 updated = taskService.updateCompletionStatus(id, isComplete);
        return ResponseEntity.ok(updated);
    }

    /**
     * Deletes a task by its ID.
     *
     * <p>
     * Endpoint: {@code DELETE /v2/api/tasks/{id}}
     * </p>
     *
     * <p>
     * Supports optional deletion of an entire recurring series.
     * </p>
     *
     * @param id           task ID
     * @param deleteSeries if {@code true}, deletes all tasks in the series;
     *                     if {@code false}, deletes only the specified task
     * @return {@code 204 No Content} on success
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteTask(
            @PathVariable Long id,
            @RequestParam(name = "deleteSeries", defaultValue = "false") boolean deleteSeries) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        taskService.deleteTask(id, deleteSeries);
        return ResponseEntity.noContent().build();
    }

}