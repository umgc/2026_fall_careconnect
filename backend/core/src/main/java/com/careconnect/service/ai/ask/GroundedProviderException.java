package com.careconnect.service.ai.ask;

/** Internal typed failure from the grounded model adapter. */
public final class GroundedProviderException extends RuntimeException {

    public enum Kind {
        CONFIGURATION,
        PROVIDER
    }

    private final Kind kind;

    public GroundedProviderException(
            final Kind kind, final String message, final Throwable cause) {
        super(message, cause);
        this.kind = kind;
    }

    public Kind getKind() {
        return kind;
    }
}
