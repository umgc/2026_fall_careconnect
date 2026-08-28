package com.careconnect.service.ai.ask;

/** Raised when the model responds but violates the grounded claim/citation schema. */
public class GroundedOutputValidationException extends RuntimeException {

    /**
     * Which specific way the model's output failed to satisfy the grounded response
     * contract — lets callers pick an accurate, distinct user-facing message and retry
     * policy instead of treating every validation failure identically.
     */
    public enum Kind {
        /** The model returned no text at all. */
        EMPTY_RESPONSE,
        /** The response parsed but had no claims array (or an empty one). */
        MISSING_CLAIMS,
        /** A claim was missing its text or its extractive evidence/citation. */
        INCOMPLETE_CLAIM,
        /** The response body itself could not be parsed as JSON, or Bedrock's response
         *  envelope could not be interpreted. */
        MALFORMED_RESPONSE,
    }

    private final Kind kind;

    public GroundedOutputValidationException(final String message, final Kind kind) {
        super(message);
        this.kind = kind;
    }

    public GroundedOutputValidationException(final String message, final Kind kind, final Throwable cause) {
        super(message, cause);
        this.kind = kind;
    }

    public Kind kind() {
        return kind;
    }
}
