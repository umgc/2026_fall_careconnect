package com.careconnect.exception;

/**
 * Provider API rejected the access token (typically HTTP 401/403).
 * Callers should invalidate the credential and halt sync.
 */
public class EmailAuthException extends RuntimeException {

    public EmailAuthException(final String message) {
        super(message);
    }

    public EmailAuthException(final String message, final Throwable cause) {
        super(message, cause);
    }
}
