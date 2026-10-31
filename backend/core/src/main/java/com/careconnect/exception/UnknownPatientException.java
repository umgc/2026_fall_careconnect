package com.careconnect.exception;

public class UnknownPatientException extends RuntimeException {

    public UnknownPatientException() {
        super("Patient not found");
    }

    public UnknownPatientException(final String message) {
        super(message);
    }

    public UnknownPatientException(final String message, final Throwable cause) {
        super(message, cause);
    }

    public UnknownPatientException(final Throwable cause) {
        super(cause);
    }
}

