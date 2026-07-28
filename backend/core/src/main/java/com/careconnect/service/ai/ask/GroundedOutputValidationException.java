package com.careconnect.service.ai.ask;

/** Raised when the model responds but violates the grounded claim/citation schema. */
public class GroundedOutputValidationException extends RuntimeException {

    public GroundedOutputValidationException(final String message) {
        super(message);
    }

    public GroundedOutputValidationException(final String message, final Throwable cause) {
        super(message, cause);
    }
}
