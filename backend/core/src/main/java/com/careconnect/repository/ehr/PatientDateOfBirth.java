package com.careconnect.repository.ehr;

/**
 * A patient who has rows past a retention cutoff in one of the {@code ehr_*} tables, and their
 * stored date of birth. What the retention purge needs to decide whether those rows may go; see
 * {@code EhrRetentionWorker}.
 */
public interface PatientDateOfBirth {

    Long getPatientId();

    /**
     * {@code patient.dob} exactly as stored: free text in two formats, possibly null. Also null
     * when no {@code patient} row exists for the id, which the purge treats the same way, as
     * unknown.
     */
    String getDob();
}
