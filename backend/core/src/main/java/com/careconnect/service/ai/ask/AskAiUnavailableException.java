package com.careconnect.service.ai.ask;

import org.springframework.http.HttpStatus;

import java.util.UUID;

/**
 * Raised when Ask AI cannot complete grounded inference (Bedrock unavailable / empty).
 */
public class AskAiUnavailableException extends AskAiException {

    public AskAiUnavailableException(final String message) {
        this("RETRIEVAL_UNAVAILABLE", message);
    }

    public AskAiUnavailableException(final String errorCode, final String message) {
        this(null, null, null, errorCode, message, null);
    }

    public AskAiUnavailableException(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String errorCode,
            final String message,
            final Throwable cause) {
        super(
                requestId,
                auditId,
                sessionId,
                errorCode == null ? "RETRIEVAL_UNAVAILABLE" : errorCode,
                HttpStatus.SERVICE_UNAVAILABLE,
                message,
                cause);
    }
}
