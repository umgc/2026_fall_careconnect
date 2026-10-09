package com.careconnect.service.ehr.athena;

/** A sync for this user is already running; a second one would race it on the same rows. */
public class AthenaSyncInProgressException extends RuntimeException {

    public AthenaSyncInProgressException() {
        super("an athenahealth sync is already running for this user");
    }
}
