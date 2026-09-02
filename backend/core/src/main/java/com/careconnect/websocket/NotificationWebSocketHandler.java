package com.careconnect.websocket;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.util.concurrent.ConcurrentHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentMap;

@Component
public class NotificationWebSocketHandler extends TextWebSocketHandler {
    private static final Logger logger = LoggerFactory.getLogger(NotificationWebSocketHandler.class);
    // sessionId -> session
    private final Map<String, WebSocketSession> sessions = new ConcurrentHashMap<>();
    // userId -> sessionId
    private final ConcurrentMap<String, String> userSessionMap = new ConcurrentHashMap<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        sessions.put(session.getId(), session);
        logger.info("WebSocket connection established: {}", session.getId());
        // Expect client to send userId as first message
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        logger.info("Received message from {}: {}", session.getId(), message.getPayload());
        // If this is the first message, treat it as userId registration
        String payload = message.getPayload();
        if (payload.startsWith("REGISTER_USER:")) {
            String userId = payload.substring("REGISTER_USER:".length());
            userSessionMap.put(userId, session.getId());
            logger.info("Registered user {} to session {}", userId, session.getId());
            session.sendMessage(new TextMessage("User registered: " + userId));
        } else {
            // Echo for other messages
            session.sendMessage(new TextMessage("Echo: " + payload));
        }
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
