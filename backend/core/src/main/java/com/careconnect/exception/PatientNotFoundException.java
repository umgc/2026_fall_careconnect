package com.careconnect.exception;

/**
 * Thrown when a Patient cannot be found.
 */
public class PatientNotFoundException extends NotFoundException {
    public PatientNotFoundException(Long patientId) {
        super("Patient not found: id=" + patientId);
    }

    public PatientNotFoundException(String message) {
        super(message);
    }
}
