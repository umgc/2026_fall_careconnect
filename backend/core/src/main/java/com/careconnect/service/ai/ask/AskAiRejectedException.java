package com.careconnect.service.ai.ask;

import org.springframework.http.HttpStatus;

import java.util.UUID;

/**
 * Raised when Ask AI rejects a request before retrieval (rate limit, sanitization, etc.).
 */
public class AskAiRejectedException extends AskAiException {

    public AskAiRejectedException(
            final String errorCode, final String message, final int httpStatus) {
        this(null, null, null, errorCode, message, httpStatus);
    }

    public AskAiRejectedException(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String errorCode,
            final String message,
            final int httpStatus) {
        super(
                requestId,
                auditId,
                sessionId,
                errorCode,
                HttpStatus.valueOf(httpStatus),
                message,
                null);
    }

    public int getHttpStatus() {
        return getStatus().value();
    }
}
