package com.careconnect.exception;

/**
 * Custom exception for OAuth-related errors with specific error types
 */
public class OAuthException extends RuntimeException {

    private final String errorType;

    public OAuthException(String message, String errorType) {
        super(message);
        this.errorType = errorType;
    }

    public OAuthException(String message, String errorType, Throwable cause) {
        super(message, cause);
        this.errorType = errorType;
    }

    public String getErrorType() {
        return errorType;
    }
}
