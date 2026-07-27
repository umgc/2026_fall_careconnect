package com.careconnect.dto;

import java.time.Instant;

/**
 * Rich Gmail connection status for USPS Informed Delivery (Task 3.14.9).
 */
public record EmailConnectionStatusResponse(
        boolean connected,
        boolean needsReconnect,
        boolean syncEnabled,
        String status,
        String provider,
        Instant expiresAt,
        String lastError,
        String reconnectPath
) {
    public static EmailConnectionStatusResponse disconnected() {
        return new EmailConnectionStatusResponse(
                false,
                false,
                false,
                "DISCONNECTED",
                "GMAIL",
                null,
                null,
                "/oauth/google/start");
    }
}
