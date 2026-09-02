package com.careconnect.websocket;

import com.careconnect.model.Message;
import com.careconnect.repository.MessageRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * WebSocket handler for real-time Person-to-Person chat messages.
 * <p>
 * Connection Flow:
 * 1. Client connects to /ws/chat
 * 2. Sends authentication message with userId
 * 3. Handler routes incoming messages to recipient's WebSocket session
 * 4. If recipient offline, messages are persisted in database
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ChatMessageWebSocketHandler extends TextWebSocketHandler {

    private final MessageRepository messageRepository;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // Track active connections: userId (String) -> WebSocketSession
    private final Map<String, WebSocketSession> userSessions = new ConcurrentHashMap<>();

    // Track session info: sessionId -> userId
    private final Map<String, String> sessionUserMap = new ConcurrentHashMap<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        log.info("Chat WebSocket connection established: {}", session.getId());

        // Send welcome message
        Map<String, Object> response = Map.of(
                "type", "connection-established",
                "message", "Connected to CareConnect chat service",
                "sessionId", session.getId()
        );
        session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        try {
            Map<String, Object> payload = objectMapper.readValue(
                    message.getPayload(),
                    new com.fasterxml.jackson.core.type.TypeReference<Map<String, Object>>() {
                    }
            );

            String messageType = (String) payload.get("type");
            log.debug("Received chat message type: {} from session: {}", messageType, session.getId());

            switch (messageType) {
                case "authenticate":
                    handleAuthenticate(session, payload);
                    break;
                case "message":
                    handleChatMessage(session, payload);
                    break;
                case "typing":
                    handleTypingIndicator(session, payload);
                    break;
                case "read-receipt":
                    handleReadReceipt(session, payload);
                    break;
                default:
                    log.warn("Unknown message type: {}", messageType);
                    sendError(session, "Unknown message type: " + messageType);
            }
        } catch (Exception e) {
            log.error("Error handling chat message", e);
            sendError(session, "Error processing message: " + e.getMessage());
        }
    }

    /**
     * Authenticate user and register their WebSocket session
     */
    private void handleAuthenticate(WebSocketSession session, Map<String, Object> payload) throws Exception {
        String userId = (String) payload.get("userId");
        if (userId == null || userId.isEmpty()) {
            sendError(session, "Missing userId in authentication message");
            return;
        }

        // Register this session
        userSessions.put(userId, session);
        sessionUserMap.put(session.getId(), userId);

        log.info("User {} authenticated in chat WebSocket (sessionId: {})", userId, session.getId());

        // Send confirmation
        Map<String, Object> response = Map.of(
                "type", "authenticated",
                "userId", userId,
                "message", "Successfully authenticated"
        );
        session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
    }

    /**
     * Route message from sender to recipient
     */
    private void handleChatMessage(WebSocketSession session, Map<String, Object> payload) throws Exception {
        String authenticatedUserId = sessionUserMap.get(session.getId());
        if (authenticatedUserId == null || authenticatedUserId.isEmpty()) {
            sendError(session, "Not authenticated for chat messaging");
            return;
        }

        String senderId = authenticatedUserId;
        String recipientId = (String) payload.get("recipientId");
        String content = (String) payload.get("content");
        Object messageIdObj = payload.get("messageId");

        if (recipientId == null || content == null) {
            sendError(session, "Missing required fields: recipientId, content");
            return;
        }

        String clientMessageId = messageIdObj != null ? (String) messageIdObj : null;

        // Persist message to database
        Message message = new Message();
        message.setSenderId(Long.parseLong(senderId));
        message.setReceiverId(Long.parseLong(recipientId));
        message.setContent(content);
        message.setTimestamp(java.time.LocalDateTime.now());
        message.setRead(false);

        Message savedMessage = messageRepository.save(message);
        log.info("Message saved to DB: id={}, from {} to {}", savedMessage.getId(), senderId, recipientId);

        // Try to deliver message to recipient if online
        WebSocketSession recipientSession = userSessions.get(recipientId);
        boolean delivered = false;

        if (recipientSession != null && recipientSession.isOpen()) {
            try {
                Map<String, Object> deliveryPayload = Map.of(
                        "type", "message-received",
                        "messageId", savedMessage.getId(),
                        "clientMessageId", clientMessageId != null ? clientMessageId : "",
                        "senderId", senderId,
                        "recipientId", recipientId,
                        "content", content,
                        "timestamp", savedMessage.getTimestamp().toString(),
                        "delivered", true
                );
                recipientSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(deliveryPayload)));
                delivered = true;
                log.info("Message {} delivered to user {}", savedMessage.getId(), recipientId);
            } catch (Exception e) {
                log.error("Failed to deliver message to user {}: {}", recipientId, e.getMessage());
            }
        }

        // Send acknowledgment to sender
        Map<String, Object> ack = Map.of(
                "type", "message-sent",
                "clientMessageId", clientMessageId != null ? clientMessageId : "",
                "messageId", savedMessage.getId(),
                "delivered", delivered,
                "timestamp", savedMessage.getTimestamp().toString()
        );
        session.sendMessage(new TextMessage(objectMapper.writeValueAsString(ack)));
    }

    /**
     * Handle typing indicators (optional, for UX)
     */
    private void handleTypingIndicator(WebSocketSession session, Map<String, Object> payload) throws Exception {
        String senderId = sessionUserMap.get(session.getId());
        String recipientId = (String) payload.get("recipientId");
        Boolean isTyping = (Boolean) payload.get("isTyping");

        if (senderId == null || recipientId == null) {
            if (senderId == null) {
                sendError(session, "Not authenticated for typing indicator");
            }
            return;
        }

        WebSocketSession recipientSession = userSessions.get(recipientId);
        if (recipientSession != null && recipientSession.isOpen()) {
            try {
                Map<String, Object> typingPayload = Map.of(
                        "type", "user-typing",
                        "senderId", senderId,
                        "isTyping", isTyping != null ? isTyping : true
                );
                recipientSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(typingPayload)));
            } catch (Exception e) {
                log.debug("Failed to send typing indicator", e);
            }
        }
    }

    /**
     * Handle read receipts
     */
    private void handleReadReceipt(WebSocketSession session, Map<String, Object> payload) throws Exception {
        String recipientId = sessionUserMap.get(session.getId());
        Object messageIdObj = payload.get("messageId");

        if (recipientId == null || messageIdObj == null) {
            if (recipientId == null) {
                sendError(session, "Not authenticated for read receipt");
            }
            return;
        }

        try {
            Long messageId = Long.parseLong(messageIdObj.toString());
            Optional<Message> optionalMessage = messageRepository.findById(messageId);

            if (optionalMessage.isPresent()) {
                Message msg = optionalMessage.get();
                msg.setRead(true);
                messageRepository.save(msg);
                log.debug("Message {} marked as read", messageId);

                // Notify sender that message was read
                WebSocketSession senderSession = userSessions.get(msg.getSenderId().toString());
                if (senderSession != null && senderSession.isOpen()) {
                    Map<String, Object> readPayload = Map.of(
                            "type", "message-read",
                            "messageId", messageId,
                            "recipientId", recipientId
                    );
                    senderSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(readPayload)));
                }
            }
        } catch (NumberFormatException e) {
            log.debug("Invalid message ID format", e);
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) throws Exception {
        String userId = sessionUserMap.remove(session.getId());
        if (userId != null) {
            userSessions.remove(userId);
            log.info("User {} disconnected from chat WebSocket", userId);
        }
    }

    /**
     * Send error message to client
     */
    private void sendError(WebSocketSession session, String errorMessage) {
        try {
            Map<String, Object> errorPayload = Map.of(
                    "type", "error",
                    "message", errorMessage
            );
            session.sendMessage(new TextMessage(objectMapper.writeValueAsString(errorPayload)));
        } catch (Exception e) {
            log.error("Failed to send error message", e);
        }
    }

    /**
     * Broadcast message to all connected users (admin notifications, etc.)
     */
    public void broadcastMessage(String messageType, Map<String, Object> data) {
        userSessions.values().forEach(session -> {
            if (session.isOpen()) {
                try {
                    Map<String, Object> payload = new HashMap<>(data);
                    payload.put("type", messageType);
                    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(payload)));
                } catch (Exception e) {
                    log.debug("Failed to broadcast message", e);
                }
            }
        });
    }

    /**
     * Get active users count (for monitoring)
     */
    public int getActiveUsersCount() {
        return userSessions.size();
    }
}
