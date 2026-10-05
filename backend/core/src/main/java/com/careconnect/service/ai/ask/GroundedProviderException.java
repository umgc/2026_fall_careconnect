package com.careconnect.service.ai.ask;

/**
 * Internal typed failure from the grounded model adapter.
 */
public final class GroundedProviderException extends RuntimeException {

    private final Kind kind;
    private final boolean transientFailure;
    public GroundedProviderException(
            final Kind kind, final String message, final Throwable cause) {
        this(kind, kind == Kind.PROVIDER, message, cause);
    }

    public GroundedProviderException(
            final Kind kind,
            final boolean transientFailure,
            final String message,
            final Throwable cause) {
        super(message, cause);
        this.kind = kind;
        this.transientFailure = transientFailure;
    }

    public Kind getKind() {
        return kind;
    }

    public boolean isTransientFailure() {
        return transientFailure;
    }

    public enum Kind {
        CONFIGURATION,
        PROVIDER
    }
}
