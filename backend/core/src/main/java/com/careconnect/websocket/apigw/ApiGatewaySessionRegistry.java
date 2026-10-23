package com.careconnect.websocket.apigw;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Open API Gateway connections, keyed by connection id.
 *
 * <p>Held in memory, so every message for a connection must reach this same task. That is why the
 * service runs a single ECS task; scaling out needs this moved to the database.
 */
public class ApiGatewaySessionRegistry {

    private final Map<String, ApiGatewayWebSocketSession> sessions = new ConcurrentHashMap<>();

    public void register(final ApiGatewayWebSocketSession session) {
        sessions.put(session.getId(), session);
    }

    /** Returns the session, or {@code null} when this task does not know the connection. */
    public ApiGatewayWebSocketSession get(final String connectionId) {
        return sessions.get(connectionId);
    }

    /** Removes and returns the session, or {@code null} when it was not registered. */
    public ApiGatewayWebSocketSession remove(final String connectionId) {
        return sessions.remove(connectionId);
    }

    public int size() {
        return sessions.size();
    }
}
