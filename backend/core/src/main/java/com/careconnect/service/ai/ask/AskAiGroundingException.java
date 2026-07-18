package com.careconnect.service.ai.ask;

/**
 * Raised when an upstream model response cannot satisfy the citation grounding contract.
 *
 * <p>This is distinct from infrastructure unavailability: callers receive HTTP 502 and
 * should not automatically retry it as a transient service outage.
 */
public class AskAiGroundingException extends RuntimeException {

    public static final String ERROR_CODE = "UNGROUNDED_RESPONSE";

    public AskAiGroundingException(final String message) {
        super(message);
    }

    public String getErrorCode() {
        return ERROR_CODE;
    }
}
