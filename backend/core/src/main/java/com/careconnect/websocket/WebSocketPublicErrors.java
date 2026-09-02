package com.careconnect.websocket;

/**
 * Stable public WebSocket error codes and messages. Exception details stay in server logs only.
 */
public final class WebSocketPublicErrors {

    public static final String CODE_INTERNAL = "INTERNAL_ERROR";
    public static final String MSG_INTERNAL = "Unable to process message";

    public static final String CODE_UNAUTHENTICATED = "UNAUTHENTICATED";
    public static final String MSG_UNAUTHENTICATED = "User not authenticated";

    public static final String CODE_UNKNOWN_TYPE = "UNKNOWN_TYPE";
    public static final String MSG_UNKNOWN_TYPE = "Unknown message type";

    public static final String CODE_NOT_FOUND = "NOT_FOUND";
    public static final String MSG_RECIPIENT_NOT_FOUND = "Recipient not found";

    public static final String CODE_INVALID_REQUEST = "INVALID_REQUEST";
    public static final String MSG_INVALID_CHANNEL = "Invalid channel";
    public static final String MSG_MISSING_OTHER_PARTY = "otherPartyId is required";
    public static final String MSG_EMAIL_REQUIRED = "Email is required for email verification subscription";

    private WebSocketPublicErrors() {
    }
}
