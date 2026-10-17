package com.careconnect.dto;

/**
 * Request body for a patient confirming the open {@code date_of_birth} identity conflict raised by
 * an Epic demographics reconcile (Cononical_5_1 Step 7).
 *
 * @param acceptIncoming {@code true} to apply Epic's incoming date of birth to the patient record;
 *                       {@code false} to keep the existing value. Required.
 */
public record EpicDobConfirmationRequest(Boolean acceptIncoming) {
}
