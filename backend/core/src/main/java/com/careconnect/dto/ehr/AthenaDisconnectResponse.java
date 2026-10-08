package com.careconnect.dto.ehr;

import com.careconnect.service.ehr.EhrSourceDataPurger;

/**
 * Result of {@code POST /api/athena/disconnect}, returned only after the deletes have committed.
 *
 * @param disconnected always true; a failure is an error response instead
 * @param removed      rows deleted per table
 */
public record AthenaDisconnectResponse(boolean disconnected, EhrSourceDataPurger.Purged removed) {
}
