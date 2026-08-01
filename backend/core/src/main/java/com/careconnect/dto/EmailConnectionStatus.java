package com.careconnect.dto;

import com.careconnect.model.EmailCredential;

import java.time.Instant;

/**
 * Structured Gmail/Outlook connection status for reconnect UX.
 */
public record EmailConnectionStatus(
        boolean connected,
        String status,
        EmailCredential.Provider provider,
        Instant expiresAt,
        String message
) {
    public static final String STATUS_CONNECTED = "CONNECTED";
    public static final String STATUS_NOT_CONNECTED = "NOT_CONNECTED";
    public static final String STATUS_EXPIRED = "EXPIRED";
    public static final String STATUS_NEEDS_RECONNECT = "NEEDS_RECONNECT";

    public static EmailConnectionStatus notConnected(EmailCredential.Provider provider) {
        return new EmailConnectionStatus(
                false,
                STATUS_NOT_CONNECTED,
                provider,
                null,
                "No Gmail account connected. Connect to fetch USPS digests automatically."
        );
    }

    public static EmailConnectionStatus connected(EmailCredential.Provider provider, Instant expiresAt) {
        return new EmailConnectionStatus(
                true,
                STATUS_CONNECTED,
                provider,
                expiresAt,
                "Gmail account connected."
        );
    }

    public static EmailConnectionStatus needsReconnect(EmailCredential.Provider provider, String message) {
        return new EmailConnectionStatus(
                false,
                STATUS_NEEDS_RECONNECT,
                provider,
                null,
                message
        );
    }
}
