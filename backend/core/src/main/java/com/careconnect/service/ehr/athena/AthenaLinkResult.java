package com.careconnect.service.ehr.athena;

/**
 * Outcome of linking a CareConnect patient to an athenahealth chart.
 *
 * @param state           what happened; its name is the code the API returns
 * @param athenaPatientId the linked chart, present only when {@code state} is {@link State#LINKED}
 */
public record AthenaLinkResult(State state, String athenaPatientId) {

    /** Why a patient is, or is not, linked. */
    public enum State {
        LINKED,
        /** The signed-in user has no patient profile to match on. */
        NO_PATIENT_PROFILE,
        /** First name, last name or a readable date of birth is missing from the profile. */
        INCOMPLETE_PROFILE,
        /** No athena chart matches exactly. */
        NOT_MATCHED,
        /** More than one chart matches exactly, so none can be chosen safely. */
        AMBIGUOUS_MATCH,
        /** The matching chart is already linked to a different CareConnect patient. */
        LINK_CONFLICT,
        /** athena could not be searched: unreachable, no token, or the source is not registered. */
        SOURCE_UNAVAILABLE
    }

    static AthenaLinkResult linked(final String athenaPatientId) {
        return new AthenaLinkResult(State.LINKED, athenaPatientId);
    }

    static AthenaLinkResult of(final State state) {
        return new AthenaLinkResult(state, null);
    }

    public boolean isLinked() {
        return state == State.LINKED;
    }
}
