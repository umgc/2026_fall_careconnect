package com.careconnect.websocket.apigw;

import java.util.Arrays;
import java.util.Optional;

/**
 * The websocket channels a client can open through the API Gateway WebSocket API.
 *
 * <p>API Gateway exposes a single URL per stage, so the channel is chosen with the {@code channel}
 * query-string parameter on connect. Each value corresponds to one local Spring endpoint.
 */
public enum WebSocketChannel {
    /** Call signaling — local {@code /ws/calls-ws}. */
    CALLS("calls"),
    /** General real-time updates and email verification — local {@code /ws/careconnect}. */
    CARECONNECT("careconnect"),
    /** Plain-text notifications — local {@code /ws/notifications}. */
    NOTIFICATIONS("notifications"),
    /** Person-to-person chat — local {@code /ws/chat}. */
    CHAT("chat");

    private final String queryValue;

    WebSocketChannel(final String queryValue) {
        this.queryValue = queryValue;
    }

    /**
     * Resolves the {@code channel} query-string value sent on connect.
     *
     * @param value raw query value (may be null)
     * @return the channel, or empty when the value is missing or unknown
     */
    public static Optional<WebSocketChannel> fromQueryValue(final String value) {
        return Arrays.stream(values()).filter(c -> c.queryValue.equals(value)).findFirst();
    }
}
