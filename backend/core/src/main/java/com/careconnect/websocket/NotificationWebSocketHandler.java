package com.careconnect.websocket;

import com.careconnect.model.User;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.util.concurrent.ConcurrentHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentMap;

/**
 * Plain-text notification channel. Clients authenticate with
 * {@code {"type":"authenticate","token":"<jwt>"}}; the user id is taken from the token.
 */
@Component
public class NotificationWebSocketHandler extends TextWebSocketHandler {
    private static final Logger logger = LoggerFactory.getLogger(NotificationWebSocketHandler.class);
    private static final String LEGACY_REGISTER_PREFIX = "REGISTER_USER:";

    private final WebSocketJwtAuthenticator authenticator;
    private final ObjectMapper objectMapper = new ObjectMapper();
    // sessionId -> session
    private final Map<String, WebSocketSession> sessions = new ConcurrentHashMap<>();
    // userId -> sessionId
    private final ConcurrentMap<String, String> userSessionMap = new ConcurrentHashMap<>();

    public NotificationWebSocketHandler(WebSocketJwtAuthenticator authenticator) {
        this.authenticator = authenticator;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        sessions.put(session.getId(), session);
        logger.info("WebSocket connection established: {}", session.getId());
        // Expect client to send an authenticate message first
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        String payload = message.getPayload();
        Map<String, Object> json = parseJson(payload);
        if ("authenticate".equals(json.get("type"))) {
            handleAuthenticate(session, json);
        } else if (payload.startsWith(LEGACY_REGISTER_PREFIX)) {
            // Unauthenticated registration let any client claim any user id.
            sendJson(session, Map.of(
                    "type", "authentication-failed",
                    "message", "REGISTER_USER is no longer supported; send authenticate with a token"));
        } else {
            // Echo for other messages
            session.sendMessage(new TextMessage("Echo: " + payload));
        }
    }

    private void handleAuthenticate(WebSocketSession session, Map<String, Object> json) throws Exception {
        Optional<User> user = authenticator.authenticate(json.get("token"));
        if (user.isEmpty()) {
            sendJson(session, Map.of("type", "authentication-failed", "message", "Invalid or missing token"));
            session.close(CloseStatus.NOT_ACCEPTABLE.withReason("Authentication failed"));
            return;
        }
        String userId = user.get().getId().toString();
        userSessionMap.put(userId, session.getId());
        logger.info("Registered user {} to session {}", userId, session.getId());
        sendJson(session, Map.of("type", "authentication-success", "userId", userId));
    }

    private Map<String, Object> parseJson(String payload) {
        try {
            Map<String, Object> parsed = objectMapper.readValue(payload, new TypeReference<Map<String, Object>>() { });
            return parsed == null ? Map.of() : parsed;
        } catch (JsonProcessingException e) {
            return Map.of();
        }
    }

    private void sendJson(WebSocketSession session, Map<String, Object> body) throws Exception {
        session.sendMessage(new TextMessage(objectMapper.writeValueAsString(body)));
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) throws Exception {
        sessions.remove(session.getId());
        // Remove user mapping if present
        userSessionMap.entrySet().removeIf(entry -> entry.getValue().equals(session.getId()));
        logger.info("WebSocket connection closed: {}", session.getId());
    }

    public void sendNotificationToAll(String notification) {
        sessions.values().forEach(session -> {
            if (session.isOpen()) {
                try {
                    session.sendMessage(new TextMessage(notification));
                } catch (Exception e) {
                    logger.error("Failed to send notification to {}: {}", session.getId(), e.getMessage());
                }
            }
        });
    }

    public boolean sendNotificationToUser(String userId, String notification) {
        String sessionId = userSessionMap.get(userId);
        if (sessionId != null) {
            WebSocketSession session = sessions.get(sessionId);
            if (session != null && session.isOpen()) {
                try {
                    session.sendMessage(new TextMessage(notification));
                    return true;
                } catch (Exception e) {
                    logger.error("Failed to send notification to user {}: {}", userId, e.getMessage());
                    return false;
                }
            }
        } else {
            logger.warn("No active WebSocket session for user {}", userId);
        }
        return false;
    }
}
