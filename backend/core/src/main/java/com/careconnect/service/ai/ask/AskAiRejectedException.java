package com.careconnect.service.ai.ask;

/**
 * Raised when Ask AI rejects a request before retrieval (rate limit, sanitization, etc.).
 */
public class AskAiRejectedException extends RuntimeException {

    private final String errorCode;
    private final int httpStatus;

    public AskAiRejectedException(
            final String errorCode, final String message, final int httpStatus) {
        super(message);
        this.errorCode = errorCode;
        this.httpStatus = httpStatus;
    }

    public String getErrorCode() {
        return errorCode;
    }

    public int getHttpStatus() {
        return httpStatus;
    }
}
