package com.careconnect.service;

/**
 * Indicates that a remote summary model invocation failed.
 */
public class ModelInferenceException extends RuntimeException {

    public ModelInferenceException(final String message, final Throwable cause) {
        super(message, cause);
    }
}
