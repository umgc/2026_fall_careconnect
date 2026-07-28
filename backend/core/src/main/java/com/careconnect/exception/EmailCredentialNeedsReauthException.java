package com.careconnect.exception;

/**
 * Raised when Gmail/OAuth credentials are revoked or expired and mail sync
 * must halt until the user reconnects (Task 3.14.9 / TC-E-USPS-003).
 */
public class EmailCredentialNeedsReauthException extends RuntimeException {

    private final String userId;
    private final String reconnectPath;

    public EmailCredentialNeedsReauthException(final String userId, final String message) {
        this(userId, message, "/oauth/google/start");
    }

    public EmailCredentialNeedsReauthException(
            final String userId,
            final String message,
            final String reconnectPath) {
        super(message);
        this.userId = userId;
        this.reconnectPath = reconnectPath;
    }

    public String getUserId() {
        return userId;
    }

    public String getReconnectPath() {
        return reconnectPath;
    }
}
