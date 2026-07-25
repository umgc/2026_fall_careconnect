package com.careconnect.dto;

import java.time.Instant;

/**
 * Rich email connection status for USPS Informed Delivery (multi-provider).
 */
public record EmailConnectionStatusResponse(
        boolean connected,
        boolean needsReconnect,
        boolean syncEnabled,
        String status,
        String provider,
        String authMode,
        Instant expiresAt,
        String lastError,
        String reconnectPath,
        String emailAddress
) {
    public static EmailConnectionStatusResponse disconnected() {
        return new EmailConnectionStatusResponse(
                false,
                false,
                false,
                "DISCONNECTED",
                "GMAIL",
                "OAUTH",
                null,
                null,
                "/oauth/google/start",
                null);
    }
}
