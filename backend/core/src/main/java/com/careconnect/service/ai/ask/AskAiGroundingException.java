package com.careconnect.service.ai.ask;

import org.springframework.http.HttpStatus;

import java.util.UUID;

/**
 * Raised when an upstream model response cannot satisfy the citation grounding contract.
 *
 * <p>This is distinct from infrastructure unavailability: callers receive HTTP 502 and
 * should not automatically retry it as a transient service outage.
 */
public class AskAiGroundingException extends AskAiException {

    public static final String ERROR_CODE = "UNGROUNDED_RESPONSE";

    public AskAiGroundingException(final String message) {
        this(null, null, null, message);
    }

    public AskAiGroundingException(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String message) {
        super(
                requestId,
                auditId,
                sessionId,
                ERROR_CODE,
                HttpStatus.BAD_GATEWAY,
                message,
                null);
    }
}
