package com.careconnect.websocket;

import com.careconnect.model.Message;
import com.careconnect.repository.MessageRepository;
import com.careconnect.service.MessagingPolicy;
import com.careconnect.testsupport.fixtures.UserFixtures;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
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
import static org.mockito.ArgumentMatchers.anyLong;
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
    private WebSocketJwtAuthenticator authenticator;
    @Mock
    private MessagingPolicy messagingPolicy;
    @Mock
    private WebSocketSession session;
    @Mock
    private WebSocketSession recipientSession;

    private ChatMessageWebSocketHandler handler;

    @BeforeEach
    void setUp() {
        handler = new ChatMessageWebSocketHandler(messageRepository, authenticator, messagingPolicy);
        // Every pair may message unless a test says otherwise; the rule itself is MessagingPolicyTest's
        lenient().when(messagingPolicy.canMessage(anyLong(), anyLong())).thenReturn(true);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    /**
     * Sends an authenticate message so that the given session is registered as the specified userId.
     *
     * <p>The JWT check is mocked: the token {@code "token-<userId>"} resolves to that user, so each
     * test controls which user a session belongs to without a real signing key.
     */
    private void authenticate(WebSocketSession sess, String sessionId, String userId)
            throws Exception {
        lenient().when(sess.getId()).thenReturn(sessionId);
        String token = "token-" + userId;
        lenient().when(authenticator.authenticate(token))
                .thenReturn(Optional.of(UserFixtures.userWithId(Long.valueOf(userId))));
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate", "token", token));
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
    @DisplayName("TC-MSG-WS-001 a new connection is told it is connected")
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
    @DisplayName("TC-MSG-WS-002 a frame that is not JSON gets an error")
    void handleTextMessage_invalidJson_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");

        handler.handleTextMessage(session, new TextMessage("{{{bad json"));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    // ─── authenticate ─────────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-WS-003 a valid token authenticates the session as the token's user")
    void authenticate_validToken_sendsAuthenticatedResponseWithTokenUserId() throws Exception {
        // Arrange: the token resolves to user 42
        authenticate(session, "s1", "42");

        // Assert
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(1)).sendMessage(captor.capture());
        Map<String, Object> payload =
                MAPPER.readValue(captor.getValue().getPayload(), new TypeReference<>() {
                });
        assertThat(payload.get("type")).isEqualTo("authenticated");
        assertThat(payload.get("userId")).isEqualTo("42");
    }

    /**
     * A client-supplied userId must be ignored; only the token decides who the session is.
     */
    @Test
    @DisplayName("TC-MSG-WS-004 a user id the client sends with authenticate is ignored")
    void authenticate_clientSuppliedUserIdIsIgnored() throws Exception {
        // Arrange: the token belongs to user 7, but the client claims to be user 99
        when(session.getId()).thenReturn("s1");
        when(authenticator.authenticate("token-7"))
                .thenReturn(Optional.of(UserFixtures.userWithId(7L)));
        String json = MAPPER.writeValueAsString(
                Map.of("type", "authenticate", "token", "token-7", "userId", "99"));

        // Act
        handler.handleTextMessage(session, new TextMessage(json));

        // Assert
        assertThat(captureLastPayload(session).get("userId")).isEqualTo("7");
    }

    @Test
    @DisplayName("TC-MSG-WS-005 authenticate with no token fails and closes the session")
    void authenticate_missingToken_sendsAuthenticationFailedAndCloses() throws Exception {
        // Arrange: no token → the authenticator rejects it
        when(session.getId()).thenReturn("s1");
        when(authenticator.authenticate(null)).thenReturn(Optional.empty());
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate"));

        // Act
        handler.handleTextMessage(session, new TextMessage(json));

        // Assert
        assertThat(captureLastPayload(session).get("type")).isEqualTo("authentication-failed");
        verify(session).close(any(CloseStatus.class));
        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    @DisplayName("TC-MSG-WS-006 authenticate with an invalid token fails and closes the session")
    void authenticate_invalidToken_sendsAuthenticationFailedAndCloses() throws Exception {
        // Arrange
        when(session.getId()).thenReturn("s1");
        when(authenticator.authenticate("forged")).thenReturn(Optional.empty());
        String json = MAPPER.writeValueAsString(Map.of("type", "authenticate", "token", "forged"));

        // Act
        handler.handleTextMessage(session, new TextMessage(json));

        // Assert
        assertThat(captureLastPayload(session).get("type")).isEqualTo("authentication-failed");
        verify(session).close(any(CloseStatus.class));
    }

    @Test
    @DisplayName("TC-MSG-WS-007 authenticating registers the user and counts them as active")
    void authenticate_registersUserAndUpdatesActiveCount() throws Exception {
        assertThat(handler.getActiveUsersCount()).isZero();

        authenticate(session, "s1", "100");

        assertThat(handler.getActiveUsersCount()).isEqualTo(1);
    }

    @Test
    @DisplayName("TC-MSG-WS-008 a second authentication for the same user replaces their session")
    void authenticate_secondAuthentication_replacesSession() throws Exception {
        authenticate(session, "s1", "100");
        authenticate(recipientSession, "s2", "100");

        // Count stays 1 because the same userId was re-registered
        assertThat(handler.getActiveUsersCount()).isEqualTo(1);
    }

    // ─── handleTextMessage() — chat message ───────────────────────────────────

    @Test
    @DisplayName("TC-MSG-WS-009 a chat message on an unauthenticated session gets an error")
    void chatMessage_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "2", "content", "hello"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    @DisplayName("TC-MSG-WS-010 a chat message with no recipientId gets an error")
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
    @DisplayName("TC-MSG-WS-011 a chat message with no content gets an error")
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
    @DisplayName("TC-MSG-SEC-014 a chat message to someone the sender may not message is answered message-rejected with the client's message id, and is neither saved nor delivered")
    void chatMessage_notAllowed_rejectsWithoutSavingOrDelivering() throws Exception {
        authenticate(session, "s1", "1");
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);
        when(messagingPolicy.canMessage(1L, 2L)).thenReturn(false);

        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "2", "content", "hello", "messageId", "cli-9"));

        handler.handleTextMessage(session, new TextMessage(json));

        verify(messageRepository, never()).save(any(Message.class));
        // The recipient got only its own auth confirmation
        verify(recipientSession, atMost(1)).sendMessage(any(TextMessage.class));
        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("message-rejected");
        assertThat(payload.get("clientMessageId")).isEqualTo("cli-9");
        assertThat(payload.get("message")).isEqualTo(ChatMessageWebSocketHandler.MESSAGING_NOT_ALLOWED);
    }

    @Test
    @DisplayName("TC-MSG-WS-012 a non-numeric recipientId gets Invalid recipientId and nothing is saved")
    void chatMessage_nonNumericRecipient_sendsErrorWithoutSaving() throws Exception {
        authenticate(session, "s1", "1");

        String json = MAPPER.writeValueAsString(
                Map.of("type", "message", "recipientId", "not-a-user", "content", "hello"));

        handler.handleTextMessage(session, new TextMessage(json));

        verify(messageRepository, never()).save(any(Message.class));
        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
        assertThat(payload.get("message")).isEqualTo("Invalid recipientId");
    }

    @Test
    @DisplayName("TC-MSG-WS-013 a chat message to an online recipient is saved, delivered and acknowledged")
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
    @DisplayName("TC-MSG-WS-014 a chat message to an offline recipient is saved and acknowledged as not delivered")
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
    @DisplayName("TC-MSG-WS-015 a chat message to a closed recipient session is saved and acknowledged as not delivered")
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
    @DisplayName("TC-MSG-WS-016 a failed delivery still saves the message and acknowledges it as not delivered")
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
    @DisplayName("TC-MSG-WS-017 a chat message with no client message id is handled")
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
    @DisplayName("TC-MSG-WS-018 a typing event on an unauthenticated session gets an error")
    void typingIndicator_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "2", "isTyping", true));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    @DisplayName("TC-MSG-WS-019 a typing event reaches an online recipient")
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
    @DisplayName("TC-MSG-WS-020 a typing event to an offline recipient does not throw")
    void typingIndicator_recipientOffline_doesNotThrow() throws Exception {
        authenticate(session, "s1", "1");

        String json = MAPPER.writeValueAsString(
                Map.of("type", "typing", "recipientId", "99", "isTyping", false));

        handler.handleTextMessage(session, new TextMessage(json));
        // No exception; nothing sent to recipient
    }

    @Test
    @DisplayName("TC-MSG-WS-021 a typing event to a closed session is not sent")
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
    @DisplayName("TC-MSG-WS-022 a typing event with no isTyping defaults to true")
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
    @DisplayName("TC-MSG-WS-023 a typing event with no recipientId does not throw")
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
    @DisplayName("TC-MSG-WS-024 a failed typing delivery does not propagate")
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
    @DisplayName("TC-MSG-WS-025 a read receipt on an unauthenticated session gets an error")
    void readReceipt_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    @Test
    @DisplayName("TC-MSG-WS-026 the receiver's read receipt marks the message read and tells the sender")
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
    @DisplayName("TC-MSG-WS-027 a read receipt for an unknown message does not throw")
    void readReceipt_messageNotFound_doesNotThrow() throws Exception {
        authenticate(session, "s1", "2");
        when(messageRepository.findById(999L)).thenReturn(Optional.empty());

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "999"));

        handler.handleTextMessage(session, new TextMessage(json));
        // No exception; message is just not found
    }

    // ─── deliver() ────────────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-WS-044 deliver pushes a share card to its connected receiver as message-received with shareKind and sharePatientId")
    void deliver_shareCard_pushesMessageReceivedWithShareFields() throws Exception {
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);
        Message card = savedMessage(11L, 1L, 2L, "Shared my Medicare records");
        card.setShareKind(Message.ShareKind.MEDICARE);
        card.setSharePatientId(10L);

        assertThat(handler.deliver(card)).isTrue();

        Map<String, Object> payload = captureLastPayload(recipientSession);
        assertThat(payload.get("type")).isEqualTo("message-received");
        assertThat(payload.get("messageId")).isEqualTo(11);
        assertThat(payload.get("senderId")).isEqualTo("1");
        assertThat(payload.get("content")).isEqualTo("Shared my Medicare records");
        assertThat(payload.get("shareKind")).isEqualTo("MEDICARE");
        assertThat(payload.get("sharePatientId")).isEqualTo(10);
    }

    @Test
    @DisplayName("TC-MSG-WS-045 deliver pushes a plain message without share fields")
    void deliver_plainMessage_hasNoShareFields() throws Exception {
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);

        assertThat(handler.deliver(savedMessage(12L, 1L, 2L, "hi"))).isTrue();

        Map<String, Object> payload = captureLastPayload(recipientSession);
        assertThat(payload).doesNotContainKeys("shareKind", "sharePatientId");
    }

    @Test
    @DisplayName("TC-MSG-WS-046 deliver returns false when the receiver is not connected")
    void deliver_receiverNotConnected_returnsFalse() {
        assertThat(handler.deliver(savedMessage(13L, 1L, 2L, "hi"))).isFalse();
    }

    @Test
    @DisplayName("TC-MSG-WS-047 deliver returns false when the receiver's session is closed")
    void deliver_receiverSessionClosed_returnsFalse() throws Exception {
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(false);

        assertThat(handler.deliver(savedMessage(14L, 1L, 2L, "hi"))).isFalse();
    }

    @Test
    @DisplayName("TC-MSG-WS-048 deliver returns false, without throwing, when the send fails")
    void deliver_sendThrows_returnsFalseWithoutPropagating() throws Exception {
        authenticate(recipientSession, "s2", "2");
        when(recipientSession.isOpen()).thenReturn(true);
        doThrow(new java.io.IOException("broken pipe")).when(recipientSession).sendMessage(any(TextMessage.class));

        assertThat(handler.deliver(savedMessage(15L, 1L, 2L, "hi"))).isFalse();
    }

    @Test
    @DisplayName("TC-MSG-SEC-015 a read receipt from a user who neither sent nor received the message is ignored: not marked read, sender not told")
    void readReceipt_fromSomeoneOtherThanTheReceiver_isIgnored() throws Exception {
        // User 3 neither sent nor received message 10
        authenticate(session, "s1", "3");
        authenticate(recipientSession, "s2", "1");
        when(recipientSession.isOpen()).thenReturn(true);

        Message msg = savedMessage(10L, 1L, 2L, "content");
        when(messageRepository.findById(10L)).thenReturn(Optional.of(msg));

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        assertThat(msg.isRead()).isFalse();
        verify(messageRepository, never()).save(any(Message.class));
        // The sender is not told the message was read
        verify(recipientSession, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    @DisplayName("TC-MSG-SEC-019 a read receipt from the message's own sender is ignored: not marked read, no "
            + "message-read event")
    void readReceipt_fromTheMessagesSender_isIgnored() throws Exception {
        // User 1 sent message 10 to user 2, then sends a read receipt for it
        authenticate(session, "s1", "1");
        lenient().when(session.isOpen()).thenReturn(true);

        Message msg = savedMessage(10L, 1L, 2L, "content");
        when(messageRepository.findById(10L)).thenReturn(Optional.of(msg));

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "10"));

        handler.handleTextMessage(session, new TextMessage(json));

        assertThat(msg.isRead()).isFalse();
        verify(messageRepository, never()).save(any(Message.class));
        // Only the auth confirmation reached the sender's session: no message-read event
        verify(session, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    @DisplayName("TC-MSG-WS-028 a read receipt marks the message read when the sender is offline")
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
    @DisplayName("TC-MSG-WS-029 a read receipt marks the message read and skips a closed sender session")
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
    @DisplayName("TC-MSG-WS-030 a read receipt with a non-numeric message id does not throw")
    void readReceipt_invalidMessageIdFormat_doesNotThrow() throws Exception {
        authenticate(session, "s1", "2");

        String json = MAPPER.writeValueAsString(Map.of("type", "read-receipt", "messageId", "abc"));

        handler.handleTextMessage(session, new TextMessage(json));
        // NumberFormatException caught internally
    }

    @Test
    @DisplayName("TC-MSG-WS-031 a read receipt with no message id does not throw")
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
    @DisplayName("TC-MSG-WS-032 an unknown message type gets an error")
    void unknownMessageType_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        String json = MAPPER.writeValueAsString(Map.of("type", "unknown-type"));

        handler.handleTextMessage(session, new TextMessage(json));

        Map<String, Object> payload = captureLastPayload(session);
        assertThat(payload.get("type")).isEqualTo("error");
    }

    // ─── afterConnectionClosed() ──────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-WS-033 closing an authenticated session removes the user")
    void afterConnectionClosed_authenticatedUser_removesFromMaps() throws Exception {
        authenticate(session, "s1", "42");
        assertThat(handler.getActiveUsersCount()).isEqualTo(1);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    @DisplayName("TC-MSG-WS-034 closing an unauthenticated session does not throw")
    void afterConnectionClosed_unauthenticatedSession_doesNotThrow() throws Exception {
        when(session.getId()).thenReturn("s1");

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
        // No exception
        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    @DisplayName("TC-MSG-WS-035 a session closed as going away is removed")
    void afterConnectionClosed_goingAway_removesSession() throws Exception {
        authenticate(session, "s1", "42");

        handler.afterConnectionClosed(session, CloseStatus.GOING_AWAY);

        assertThat(handler.getActiveUsersCount()).isZero();
    }

    // ─── broadcastMessage() ───────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-WS-036 a broadcast reaches every open session")
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
    @DisplayName("TC-MSG-WS-037 a broadcast skips a closed session")
    void broadcastMessage_closedSession_skips() throws Exception {
        authenticate(session, "s1", "1");
        when(session.isOpen()).thenReturn(false);

        handler.broadcastMessage("admin-notification", Map.of("info", "update"));

        // Only the auth message was sent; broadcast skipped because session is closed
        verify(session, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    @DisplayName("TC-MSG-WS-038 a failed broadcast send does not propagate")
    void broadcastMessage_sendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", "1");
        when(session.isOpen()).thenReturn(true);
        doNothing().doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.broadcastMessage("admin-notification", Map.of("info", "update"));
        // No exception escapes
    }

    @Test
    @DisplayName("TC-MSG-WS-039 a broadcast with no sessions does not throw")
    void broadcastMessage_noSessions_doesNotThrow() throws Exception {
        handler.broadcastMessage("admin-notification", Map.of("info", "update"));
        verifyNoInteractions(session);
    }

    @Test
    @DisplayName("TC-MSG-WS-040 a broadcast adds its type to the payload")
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
    @DisplayName("TC-MSG-WS-041 the active user count starts at zero")
    void getActiveUsersCount_empty_returnsZero() {
        assertThat(handler.getActiveUsersCount()).isZero();
    }

    @Test
    @DisplayName("TC-MSG-WS-042 the active user count follows authentications and disconnects")
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
    @DisplayName("TC-MSG-WS-043 a failure while sending an error does not propagate")
    void handleTextMessage_sendErrorThrows_doesNotPropagate() throws Exception {
        when(session.getId()).thenReturn("s1");
        doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.handleTextMessage(session, new TextMessage("{{{bad json"));
        // The handler catches the exception from sendError internally
    }
}
