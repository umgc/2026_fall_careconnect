package com.careconnect.service.ehr.athena;

import java.time.Instant;
import java.util.List;

/**
 * What one athenahealth sync did, per resource type, so the client can tell "no data" apart from
 * "not permitted" and "athena was unreachable" without parsing messages.
 *
 * @param status   whether the sync ran at all
 * @param syncedAt when it finished
 * @param types    one entry per resource type considered, in sync order
 */
public record AthenaSyncResult(Status status, Instant syncedAt, List<TypeResult> types) {

    /** Whether the sync ran. Individual types can still fail inside a COMPLETED sync. */
    public enum Status {
        COMPLETED,
        /** No token could be obtained, so no type was attempted. */
        SOURCE_UNAVAILABLE
    }

    /** What happened to one resource type. */
    public enum Outcome {
        /** Fetched, and at least one record was stored or refreshed. */
        STORED,
        /** Fetched successfully, but there was nothing to store. */
        EMPTY,
        /** Fetched, but none of the records could be saved; the server log has the cause. */
        FAILED,
        /** The portal app is not granted this type's scope, so it was not requested. */
        NOT_GRANTED,
        /** Requested, and athena answered 403. */
        SCOPE_DENIED,
        /** athena refused the query itself. */
        REJECTED,
        /** athena failed or could not be reached for this type. */
        UNAVAILABLE
    }

    /**
     * @param resourceType FHIR resource type
     * @param outcome      what happened
     * @param count        records stored or refreshed
     */
    public record TypeResult(String resourceType, Outcome outcome, int count) {
    }

    static AthenaSyncResult completed(final List<TypeResult> types) {
        return new AthenaSyncResult(Status.COMPLETED, Instant.now(), List.copyOf(types));
    }

    static AthenaSyncResult unavailable() {
        return new AthenaSyncResult(Status.SOURCE_UNAVAILABLE, Instant.now(), List.of());
    }
}
