package com.careconnect.integration.cerner;

/** Decides whether the authenticated CareConnect user may view a patient's data. */
public interface CernerAccessPolicy {
    boolean canView(String username, long patientId);
}
