package com.careconnect.exception;

/**
 * Thrown when a Task cannot be found.
 */
public class TaskNotFoundException extends NotFoundException {
    public TaskNotFoundException(Long taskId) {
        super("Task not found: id=" + taskId);
    }

    public TaskNotFoundException(String message) {
        super(message);
    }
}
