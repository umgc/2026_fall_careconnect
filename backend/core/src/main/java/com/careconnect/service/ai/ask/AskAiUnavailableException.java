package com.careconnect.service.ai.ask;

/**
 * Raised when Ask AI cannot complete grounded inference (Bedrock unavailable / empty).
 */
public class AskAiUnavailableException extends RuntimeException {

    private final String errorCode;

    public AskAiUnavailableException(final String message) {
        this("RETRIEVAL_UNAVAILABLE", message);
    }

    public AskAiUnavailableException(final String errorCode, final String message) {
        super(message);
        this.errorCode = errorCode == null ? "RETRIEVAL_UNAVAILABLE" : errorCode;
    }

    public String getErrorCode() {
        return errorCode;
    }
}
