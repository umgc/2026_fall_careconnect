package com.careconnect.dto;

/**
 * Request body for CR-2 record sharing: the authenticated patient shares their Medicare records,
 * read-only for 90 days, with another registered CareConnect user identified by email.
 *
 * @param recipientEmail email of the registered user to share with (required)
 */
public record MedicareShareRequest(
        String recipientEmail
) {
}
