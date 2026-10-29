package com.careconnect.controller;

import com.careconnect.dto.TaskDto;
import com.careconnect.model.Task;
import com.careconnect.service.TaskService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/v3/api/tasks")
public class TaskController {

    private final TaskService taskService;
    @Autowired
    private SecurityUtil securityUtil;
    @Autowired
    private AuthorizationService authorizationService;

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    @GetMapping
    public ResponseEntity<List<Map<String, Object>>> getAllTasks() throws UnauthorizedException {
        // Every patient's tasks: admin only.
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        return ResponseEntity.ok(taskService.getAllTasks().stream().map(this::toResponse).toList());
    }

    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getTaskById(@PathVariable Long id) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        Task task = taskService.getTaskById(id);
        authorizationService.requireTaskAccess(currentUser, task);
        return ResponseEntity.ok(toResponse(task));
    }

    @GetMapping("/patient/{patientId}")
    public ResponseEntity<List<Map<String, Object>>> getTasksByPatient(@PathVariable Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientRecordAccess(currentUser, patientId);
        List<Map<String, Object>> tasks = taskService.getTasksByPatient(patientId).stream().map(this::toResponse).toList();
        return ResponseEntity.ok(tasks);
    }

    @PostMapping("/patient/{patientId}")
    public ResponseEntity<Map<String, Object>> createTask(@PathVariable Long patientId, @RequestBody TaskDto task) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientRecordAccess(currentUser, patientId);
        authorizationService.requireWriteAccess(currentUser);
        Task created = taskService.createTask(patientId, task);
        return ResponseEntity.ok(toResponse(created));
    }

    @PostMapping("/patient/{patientId}/preview-notification")
    public ResponseEntity<Map<String, Object>> previewTaskNotification(@PathVariable Long patientId, @RequestBody TaskDto task) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientRecordAccess(currentUser, patientId);
        return ResponseEntity.ok(taskService.previewTaskNotification(patientId, task));
    }

    @PutMapping("/{id}")
    public ResponseEntity<Map<String, Object>> updateTask(@PathVariable Long id, @RequestBody TaskDto task) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireTaskAccess(currentUser, taskService.getTaskById(id));
        authorizationService.requireWriteAccess(currentUser);
        Task updated = taskService.updateTask(id, task);
        if (updated != null) {
            return ResponseEntity.ok(toResponse(updated));
        } else {
            return ResponseEntity.notFound().build();
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteTask(@PathVariable Long id) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireTaskAccess(currentUser, taskService.getTaskById(id));
        authorizationService.requireWriteAccess(currentUser);
        if (taskService.deleteTask(id)) {
            return ResponseEntity.noContent().build();
        } else {
            return ResponseEntity.notFound().build();
        }
    }

    private Map<String, Object> toResponse(Task task) {
        Map<String, Object> response = new HashMap<>();
        response.put("id", task.getId());
        response.put("patientId", task.getPatient() != null ? task.getPatient().getId() : null);
        response.put("name", task.getName());
        response.put("description", task.getDescription());
        response.put("date", task.getDate());
        response.put("timeOfDay", task.getTimeOfDay());
        response.put("isCompleted", task.isCompleted());
        response.put("frequency", task.getFrequency());
        response.put("interval", task.getTaskInterval());
        response.put("count", task.getDoCount());
        response.put("daysOfWeek", task.getDaysOfWeek());
        response.put("taskType", task.getTaskType());
        response.put("createdAt", task.getCreatedAt());
        response.put("parentTaskId", task.getParentTaskId());
        return response;
    }
}