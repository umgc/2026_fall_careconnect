package com.careconnect.websocket;

import com.careconnect.model.Message;
import com.careconnect.repository.MessageRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeast;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.atMost;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link ChatMessageWebSocketHandler}.
 *
 * <p>Covers connection lifecycle, authentication, chat message routing, typing indicators,
 * read receipts, broadcast, and active user count.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ChatMessageWebSocketHandlerTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Mock
    private MessageRepository messageRepository;
    @Mock
    private WebSocketSession session;
    @Mock
    private WebSocketSession recipientSession;

    private ChatMessageWebSocketHandler handler;

    @BeforeEach
    void setUp() {
        handler = new ChatMessageWebSocketHandler(messageRepository);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    /**
     * Sends an authenticate message so that the given session is registered as the specified userId.
     */
    private void authenticate(WebSocketSession sess, String sessionId, String userId)
            throws Exception {
        lenient().when(sess.getId()).thenReturn(sessionId);
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate", "userId", userId));
        handler.handleTextMessage(sess, new TextMessage(json));
    }

    /**
     * Extracts the last JSON payload sent to the given session.
     */
    private Map<String, Object> captureLastPayload(WebSocketSession sess) throws Exception {
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(sess, atLeastOnce()).sendMessage(captor.capture());
        String raw = captor.getValue().getPayload();
        return MAPPER.readValue(raw, new TypeReference<>() {
        });
    }

    /**
     * Builds a saved-message stub returned by the repository.
     */
    private Message savedMessage(Long id, Long senderId, Long receiverId, String content) {
        Message msg = new Message();
        msg.setSenderId(senderId);
        msg.setReceiverId(receiverId);
        msg.setContent(content);
        msg.setTimestamp(LocalDateTime.of(2026, 1, 1, 12, 0));
        msg.setRead(false);
        // Use reflection to set the id since there is no public setter
        try {
            var field = Message.class.getDeclaredField("id");
            field.setAccessible(true);
            field.set(msg, id);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        return msg;
    }

    // ─── afterConnectionEstablished() ─────────────────────────────────────────

    @Test
    void afterConnectionEstablished_sendsConnectionEstablishedMessage() throws Exception {
        when(session.getId()).thenReturn("s1");

        handler.afterConnectionEstablished(session);

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("connection-established");
        assertThat(payload.get("sessionId")).isEqualTo("s1");
        assertThat(payload.get("message")).isNotNull();
    }

    // ─── handleTextMessage() — invalid JSON ───────────────────────────────────

    @Test
    void handleTextMessage_invalidJson_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");

        handler.handleTextMessage(session, new TextMessage("{{{bad json"));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    // ─── authenticate ─────────────────────────────────────────────────────────

    @Test
    void authenticate_validUserId_sendsAuthenticatedResponse() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate", "userId", "42"));

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(1)).sendMessage(captor.capture());
        // The second message (after connection-established if any) should be the auth confirmation
        Map<String, Object> payload =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(payload.get("type")).isEqualTo("authenticated");
        assertThat(payload.get("userId")).isEqualTo("42");
    }

    @Test
    void authenticate_missingUserId_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    void authenticate_emptyUserId_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate", "userId", ""));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    void authenticate_registersUserAndUpdatesActiveCount() throws Exception {
        assertThat(handler.getActiveUsersCount()).isZero();

        authenticate(session, "s1", "100");

        assertThat(handler.getActiveUsersCount()).isEqualTo(1);
    }

    @Test
    void authenticate_secondAuthentication_replacesSession() throws Exception {
        authenticate(session, "s1", "100");
        authenticate(recipientSession, "s2", "100");

        // Count stays 1 because the same userId was re-registered
        assertThat(handler.getActiveUsersCount()).isEqualTo(1);
    }

    // ─── handleTextMessage() — chat message ───────────────────────────────────

    @Test
    void chatMessage_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "2", "content", "hello"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    void chatMessage_missingRecipientId_sendsError() throws Exception {
        authenticate(session, "s1", "1");
        String json = MAPPER.writeValueAsString(Map.of("type", "message", "content", "hello"));

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> last =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(last.get("type")).isEqualTo("error");
    }

    @Test
    void chatMessage_missingContent_sendsError() throws Exception {
        authenticate(session, "s1", "1");
        String json = MAPPER.writeValueAsString(Map.of("type", "message", "recipientId", "2"));

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> last =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(last.get("type")).isEqualTo("error");
    }

    @Test
    void chatMessage_recipientOnline_persistsAndDeliversAndAcks() throws Exception {
        // Authenticate sender
        authenticate(session, "s1", "1");
        // Authenticate recipient
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);

        Message saved = savedMessage(10L, 1L, 2L, "hello");
        when(messageRepository.save(any(Message.class))).thenReturn(saved);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "2", "content", "hello", "messageId", "cli-1"));

        handler.handleTextMessage(session, new TextMessage(json));

        // Verify message persisted
        verify(messageRepository).save(any(Message.class));

        // Verify recipient received message-received
        ArgumentCaptor<TextMessage> recipientCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(1)).sendMessage(recipientCaptor.capture());
        Map<String, Object> delivered = MAPPER.readValue(
                recipientCaptor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(delivered.get("type")).isEqualTo("message-received");
        assertThat(delivered.get("messageId")).isEqualTo(10);
        assertThat(delivered.get("content")).isEqualTo("hello");
        assertThat(delivered.get("delivered")).isEqualTo(true);

        // Verify sender received message-sent ack
        ArgumentCaptor<TextMessage> senderCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(senderCaptor.capture());
        Map<String, Object> ack = MAPPER.readValue(
                senderCaptor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(ack.get("type")).isEqualTo("message-sent");
        assertThat(ack.get("delivered")).isEqualTo(true);
        assertThat(ack.get("clientMessageId")).isEqualTo("cli-1");
    }

    @Test
    void chatMessage_recipientOffline_persistsAndAcksWithDeliveredFalse() throws Exception {
        authenticate(session, "s1", "1");
        // Recipient is NOT authenticated — no session for userId "99"

        Message saved = savedMessage(11L, 1L, 99L, "hi");
        when(messageRepository.save(any(Message.class))).thenReturn(saved);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "99", "content", "hi"));

        handler.handleTextMessage(session, new TextMessage(json));

        verify(messageRepository).save(any(Message.class));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> ack =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(ack.get("type")).isEqualTo("message-sent");
        assertThat(ack.get("delivered")).isEqualTo(false);
    }

    @Test
    void chatMessage_recipientSessionClosed_persistsAndAcksWithDeliveredFalse() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(false);

        Message saved = savedMessage(12L, 1L, 2L, "hey");
        when(messageRepository.save(any(Message.class))).thenReturn(saved);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "2", "content", "hey"));

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> ack =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(ack.get("type")).isEqualTo("message-sent");
        assertThat(ack.get("delivered")).isEqualTo(false);
    }

    @Test
    void chatMessage_recipientSendThrows_persistsAndAcksWithDeliveredFalse() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);
        // The auth message succeeds, then delivery throws
        doThrow(new RuntimeException("io")).when(recipientSession).sendMessage(any());

        Message saved = savedMessage(13L, 1L, 2L, "oops");
        when(messageRepository.save(any(Message.class))).thenReturn(saved);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "2", "content", "oops"));

        handler.handleTextMessage(session, new TextMessage(json));

        // Ack should still be sent to sender with delivered=false
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> ack =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(ack.get("type")).isEqualTo("message-sent");
        assertThat(ack.get("delivered")).isEqualTo(false);
    }

    @Test
    void chatMessage_nullMessageId_handledGracefully() throws Exception {
        authenticate(session, "s1", "1");

        Message saved = savedMessage(14L, 1L, 99L, "msg");
        when(messageRepository.save(any(Message.class))).thenReturn(saved);

        // No "messageId" key in payload
        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "99", "content", "msg"));

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> ack =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(ack.get("clientMessageId")).isEqualTo("");
    }

    // ─── typing indicator ─────────────────────────────────────────────────────

    @Test
    void typingIndicator_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "2", "isTyping", true));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    void typingIndicator_recipientOnline_sendsTypingEvent() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "2", "isTyping", true));

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> sent = MAPPER.readValue(
                captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(sent.get("type")).isEqualTo("user-typing");
        assertThat(sent.get("senderId")).isEqualTo("1");
        assertThat(sent.get("isTyping")).isEqualTo(true);
    }

    @Test
    void typingIndicator_recipientOffline_doesNotThrow() throws Exception {
        authenticate(session, "s1", "1");

        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "99", "isTyping", false));

        handler.handleTextMessage(session, new TextMessage(json));
        // No exception; nothing sent to recipient
    }

    @Test
    void typingIndicator_recipientSessionClosed_doesNotSend() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(false);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "2", "isTyping", true));

        handler.handleTextMessage(session, new TextMessage(json));

        // recipientSession got the auth message only
        verify(recipientSession, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void typingIndicator_nullIsTyping_defaultsToTrue() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);

        // Build payload without isTyping
        Map<String, Object> payload = new HashMap<>();
        payload.put("type", "typing");
        payload.put("recipientId", "2");
        String json = MAPPER.writeValueAsString(payload);

        handler.handleTextMessage(session, new TextMessage(json));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> sent = MAPPER.readValue(
                captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(sent.get("isTyping")).isEqualTo(true);
    }

    @Test
    void typingIndicator_nullRecipientId_doesNotThrow() throws Exception {
        authenticate(session, "s1", "1");

        Map<String, Object> payload = new HashMap<>();
        payload.put("type", "typing");
        payload.put("isTyping", true);
        // No recipientId
        String json = MAPPER.writeValueAsString(payload);

        handler.handleTextMessage(session, new TextMessage(json));
        // Should just return silently
    }

    @Test
    void typingIndicator_recipientSendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);
        doNothing().doThrow(new RuntimeException("io")).when(recipientSession).sendMessage(any());

        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "2", "isTyping", true));

        handler.handleTextMessage(session, new TextMessage(json));
        // No exception escapes
    }

    // ─── read receipt ─────────────────────────────────────────────────────────

    @Test
    void readReceipt_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    void readReceipt_validMessageId_marksAsReadAndNotifiesSender() throws Exception {
        // Reader is user "2"
        authenticate(session, "s1", "2");
        // Sender is user "1"
        authenticate(recipientSession, "s2", "1");
        when(recipientSession.isOpen()).thenReturn(true);

        Message msg = savedMessage(10L, 1L, 2L, "content");
        when(messageRepository.findById(10L)).thenReturn(Optional.of(msg));
        when(messageRepository.save(any(Message.class))).thenReturn(msg);

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        // Message should be marked as read
        verify(messageRepository).save(any(Message.class));
        assertThat(msg.isRead()).isTrue();

        // Sender should be notified
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> readPayload = MAPPER.readValue(
                captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(readPayload.get("type")).isEqualTo("message-read");
        assertThat(readPayload.get("messageId")).isEqualTo(10);
    }

    @Test
    void readReceipt_messageNotFound_doesNotThrow() throws Exception {
        authenticate(session, "s1", "2");
        when(messageRepository.findById(999L)).thenReturn(Optional.empty());

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "999"));

        handler.handleTextMessage(session, new TextMessage(json));
        // No exception; message is just not found
    }

    @Test
    void readReceipt_senderOffline_marksReadButDoesNotNotify() throws Exception {
        authenticate(session, "s1", "2");

        Message msg = savedMessage(10L, 99L, 2L, "content");
        when(messageRepository.findById(10L)).thenReturn(Optional.of(msg));
        when(messageRepository.save(any(Message.class))).thenReturn(msg);

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        verify(messageRepository).save(any(Message.class));
        assertThat(msg.isRead()).isTrue();
    }

    @Test
    void readReceipt_senderSessionClosed_marksReadButSkipsNotification() throws Exception {
        authenticate(session, "s1", "2");
        authenticate(recipientSession, "s2", "1");
        when(recipientSession.isOpen()).thenReturn(false);

        Message msg = savedMessage(10L, 1L, 2L, "content");
        when(messageRepository.findById(10L)).thenReturn(Optional.of(msg));
        when(messageRepository.save(any(Message.class))).thenReturn(msg);

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        assertThat(msg.isRead()).isTrue();
        // Sender session got only the auth message, no read notification
        verify(recipientSession, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void readReceipt_invalidMessageIdFormat_doesNotThrow() throws Exception {
        authenticate(session, "s1", "2");

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "abc"));

        handler.handleTextMessage(session, new TextMessage(json));
        // NumberFormatException caught internally
    }

    @Test
    void readReceipt_nullMessageId_doesNotThrow() throws Exception {
        authenticate(session, "s1", "2");

        Map<String, Object> payload = new HashMap<>();
        payload.put("type", "read-receipt");
        // No messageId
        String json = MAPPER.writeValueAsString(payload);

        handler.handleTextMessage(session, new TextMessage(json));
        // Returns silently because messageIdObj == null
    }

    // ─── unknown message type ─────────────────────────────────────────────────

    @Test
    void unknownMessageType_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "unknown-type"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    // ─── afterConnectionClosed() ──────────────────────────────────────────────

    @Test
    void afterConnectionClosed_authenticatedUser_removesFromMaps() throws Exception {
        authenticate(session, "s1", "42");
        assertThat(handler.getActiveUsersCount()).isEqualTo(1);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    void afterConnectionClosed_unauthenticatedSession_doesNotThrow() throws Exception {
        when(session.getId()).thenReturn("s1");

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
        // No exception
        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    void afterConnectionClosed_goingAway_removesSession() throws Exception {
        authenticate(session, "s1", "42");

        handler.afterConnectionClosed(session, CloseStatus.GOING_AWAY);

        assertThat(handler.getActiveUsersCount()).isZero();
    }

    // ─── broadcastMessage() ───────────────────────────────────────────────────

    @Test
    void broadcastMessage_openSessions_sendsToAll() throws Exception {
        authenticate(session, "s1", "1");
        when(session.isOpen()).thenReturn(true);
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.broadcastMessage("admin-notification", Map.of("info", "system update"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
        verify(recipientSession, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void broadcastMessage_closedSession_skips() throws Exception {
        authenticate(session, "s1", "1");
        when(session.isOpen()).thenReturn(false);

        handler.broadcastMessage("admin-notification", Map.of("info", "update"));

        // Only the auth message was sent; broadcast skipped because session is closed
        verify(session, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void broadcastMessage_sendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", "1");
        when(session.isOpen()).thenReturn(true);
        doNothing().doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.broadcastMessage("admin-notification", Map.of("info", "update"));
        // No exception escapes
    }

    @Test
    void broadcastMessage_noSessions_doesNotThrow() throws Exception {
        handler.broadcastMessage("admin-notification", Map.of("info", "update"));
        verifyNoInteractions(session);
    }

    @Test
    void broadcastMessage_addsTypeToPayload() throws Exception {
        authenticate(session, "s1", "1");
        when(session.isOpen()).thenReturn(true);

        handler.broadcastMessage("custom-type", Map.of("data", "value"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        Map<String, Object> last =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(last.get("type")).isEqualTo("custom-type");
        assertThat(last.get("data")).isEqualTo("value");
    }

    // ─── getActiveUsersCount() ────────────────────────────────────────────────

    @Test
    void getActiveUsersCount_empty_returnsZero() {
        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    void getActiveUsersCount_afterAuthenticationsAndDisconnects_returnsCorrectCount()
            throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        assertThat(handler.getActiveUsersCount()).isEqualTo(2);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
        assertThat(handler.getActiveUsersCount()).isEqualTo(1);
    }

    // ─── sendError — exception in sending error itself ────────────────────────

    @Test
    void handleTextMessage_sendErrorThrows_doesNotPropagate() throws Exception {
        when(session.getId()).thenReturn("s1");
        doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.handleTextMessage(session, new TextMessage("{{{bad json"));
        // The handler catches the exception from sendError internally
    }
}
