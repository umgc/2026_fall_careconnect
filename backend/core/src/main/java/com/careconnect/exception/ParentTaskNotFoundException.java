package com.careconnect.exception;

/**
 * Thrown when a parent task in a series cannot be found.
 */
public class ParentTaskNotFoundException extends NotFoundException {
    public ParentTaskNotFoundException(Long parentTaskId) {
        super("Parent task not found: id=" + parentTaskId);
    }
}
