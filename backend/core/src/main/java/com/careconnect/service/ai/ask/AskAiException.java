package com.careconnect.service.ai.ask;

import org.springframework.http.HttpStatus;

import java.util.UUID;

/** Base exception for Ask AI failures that must preserve request correlation. */
public abstract class AskAiException extends RuntimeException {

    private final UUID requestId;
    private final UUID auditId;
    private final UUID sessionId;
    private final String errorCode;
    private final HttpStatus status;

    protected AskAiException(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String errorCode,
            final HttpStatus status,
            final String message,
            final Throwable cause) {
        super(message, cause);
        this.requestId = requestId;
        this.auditId = auditId;
        this.sessionId = sessionId;
        this.errorCode = errorCode;
        this.status = status;
    }

    public UUID getRequestId() {
        return requestId;
    }

    public UUID getAuditId() {
        return auditId;
    }

    public UUID getSessionId() {
        return sessionId;
    }

    public String getErrorCode() {
        return errorCode;
    }

    public HttpStatus getStatus() {
        return status;
    }
}
