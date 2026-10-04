package com.careconnect.service.ehr.athena;

/**
 * A failed athenahealth FHIR call, classified by what the caller should do about it.
 *
 * <p>Carries no upstream response body: an athena {@code OperationOutcome} can echo the search
 * values that were sent, which for a patient search means name and date of birth.
 */
public class AthenaFhirException extends RuntimeException {

    /** What went wrong, from the caller's point of view. */
    public enum Kind {
        /** HTTP 403: the portal app is not granted the scope this resource type needs. */
        SCOPE_DENIED,
        /** athena refused the query itself: a 4xx, or a fatal outcome inside a 200. */
        REJECTED,
        /** athena could not be reached or failed: 5xx, 429, 401, timeout, or no token. */
        UNAVAILABLE
    }

    private final Kind kind;

    public AthenaFhirException(final Kind kind, final String message) {
        super(message);
        this.kind = kind;
    }

    public AthenaFhirException(final Kind kind, final String message, final Throwable cause) {
        super(message, cause);
        this.kind = kind;
    }

    public Kind getKind() {
        return kind;
    }
}
