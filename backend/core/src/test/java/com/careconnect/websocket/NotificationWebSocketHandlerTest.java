package com.careconnect.websocket;

import com.careconnect.testsupport.fixtures.UserFixtures;
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

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link NotificationWebSocketHandler}.
 *
 * <p>Covers JWT authentication (the user id comes from the token, never the client), rejection of
 * the legacy unauthenticated {@code REGISTER_USER:} form, echo, and delivery to registered users.
 * The JWT check is mocked through {@link WebSocketJwtAuthenticator} so no signing key is needed.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class NotificationWebSocketHandlerTest {

    @Mock
    WebSocketSession session;

    @Mock
    WebSocketJwtAuthenticator authenticator;

    private NotificationWebSocketHandler handler;

    @BeforeEach
    void setUp() throws Exception {
        handler = new NotificationWebSocketHandler(authenticator);
    }

    /**
     * Opens the session and authenticates it as {@code userId} via the token {@code "token-<id>"}.
     */
    private void authenticate(WebSocketSession sess, long userId) throws Exception {
        String token = "token-" + userId;
        when(authenticator.authenticate(token)).thenReturn(Optional.of(UserFixtures.userWithId(userId)));
        handler.handleTextMessage(sess,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"" + token + "\"}"));
    }

    private String lastPayload(WebSocketSession sess) throws Exception {
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(sess, atLeastOnce()).sendMessage(captor.capture());
        return captor.getValue().getPayload();
    }

    // ─── afterConnectionEstablished() ────────────────────────────────────────

    @Test
    void afterConnectionEstablished_storesSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        // Verify session is stored — sendNotificationToAll reaches it
        when(session.isOpen()).thenReturn(true);
        handler.sendNotificationToAll("ping");
        verify(session).sendMessage(any(TextMessage.class));
    }

    // ─── handleTextMessage() — authenticate ──────────────────────────────────

    @Test
    void authenticate_validToken_registersTokenUserAndReplies() throws Exception {
        // Arrange
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        // Act
        authenticate(session, 42L);

        // Assert: reply names the token's user, and that user is now reachable
        assertThat(lastPayload(session)).contains("authentication-success").contains("\"42\"");
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.sendNotificationToUser("42", "hello")).isTrue();
    }

    @Test
    void authenticate_invalidToken_repliesFailureClosesAndDoesNotRegister() throws Exception {
        // Arrange
        when(session.getId()).thenReturn("s1");
        when(authenticator.authenticate("forged")).thenReturn(Optional.empty());
        handler.afterConnectionEstablished(session);

        // Act
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"forged\"}"));

        // Assert
        assertThat(lastPayload(session)).contains("authentication-failed");
        verify(session).close(any(CloseStatus.class));
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.sendNotificationToUser("42", "hello")).isFalse();
    }

    /**
     * The old {@code REGISTER_USER:<id>} form let any client claim any user id, so it must no longer
     * register anything.
     */
    @Test
    void legacyRegisterUser_isRejectedAndDoesNotRegister() throws Exception {
        // Arrange
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        // Act
        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:42"));

        // Assert
        assertThat(lastPayload(session)).contains("authentication-failed");
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.sendNotificationToUser("42", "hello")).isFalse();
        verifyNoInteractions(authenticator);
    }

    // ─── handleTextMessage() — echo branch ───────────────────────────────────

    @Test
    void handleTextMessage_nonAuthPayload_echoesMessage() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        handler.handleTextMessage(session, new TextMessage("Hello world"));

        assertThat(lastPayload(session)).startsWith("Echo: ").contains("Hello world");
    }

    @Test
    void handleTextMessage_jsonNull_echoesInsteadOfFailing() throws Exception {
        // "null" parses to a null map; it must be treated like any other non-auth payload
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        handler.handleTextMessage(session, new TextMessage("null"));

        assertThat(lastPayload(session)).isEqualTo("Echo: null");
    }

    // ─── afterConnectionClosed() ─────────────────────────────────────────────

    @Test
    void afterConnectionClosed_removesSessionAndUserMapping() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        authenticate(session, 7L);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        // After close the user entry is gone → sendNotificationToUser returns false
        assertThat(handler.sendNotificationToUser("7", "msg")).isFalse();
    }

    // ─── sendNotificationToAll() ─────────────────────────────────────────────

    @Test
    void sendNotificationToAll_openSession_sendsMessage() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(true);
        handler.afterConnectionEstablished(session);

        handler.sendNotificationToAll("broadcast");

        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendNotificationToAll_closedSession_skips() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(false);
        handler.afterConnectionEstablished(session);

        handler.sendNotificationToAll("broadcast");

        verify(session, never()).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendNotificationToAll_sendThrows_doesNotPropagate() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("send error")).when(session).sendMessage(any());
        handler.afterConnectionEstablished(session);

        // Must not throw — exception is swallowed
        handler.sendNotificationToAll("broadcast");
    }

    @Test
    void sendNotificationToAll_multipleSessions_sendsToAllOpen() throws Exception {
        WebSocketSession session2 = mock(WebSocketSession.class);
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(true);
        when(session2.getId()).thenReturn("s2");
        when(session2.isOpen()).thenReturn(true);

        handler.afterConnectionEstablished(session);
        handler.afterConnectionEstablished(session2);

        handler.sendNotificationToAll("broadcast");

        verify(session).sendMessage(any(TextMessage.class));
        verify(session2).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendNotificationToAll_mixedOpenClosed_sendsOnlyToOpen() throws Exception {
        WebSocketSession session2 = mock(WebSocketSession.class);
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(true);
        when(session2.getId()).thenReturn("s2");
        when(session2.isOpen()).thenReturn(false);

        handler.afterConnectionEstablished(session);
        handler.afterConnectionEstablished(session2);

        handler.sendNotificationToAll("broadcast");

        verify(session).sendMessage(any(TextMessage.class));
        verify(session2, never()).sendMessage(any(TextMessage.class));
    }

    // ─── sendNotificationToUser() ────────────────────────────────────────────

    @Test
    void sendNotificationToUser_unknownUser_returnsFalse() throws Exception {
        assertThat(handler.sendNotificationToUser("nobody", "msg")).isFalse();
    }

    @Test
    void sendNotificationToUser_sessionClosed_returnsFalse() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        authenticate(session, 8L);

        when(session.isOpen()).thenReturn(false);

        assertThat(handler.sendNotificationToUser("8", "msg")).isFalse();
    }

    @Test
    void sendNotificationToUser_sendThrows_returnsFalse() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(true);
        // First call (authentication reply) succeeds; second (notification) throws
        doNothing()
                .doThrow(new RuntimeException("send fail"))
                .when(session).sendMessage(any());
        handler.afterConnectionEstablished(session);
        authenticate(session, 9L);

        assertThat(handler.sendNotificationToUser("9", "msg")).isFalse();
    }

    @Test
    void sendNotificationToUser_afterDisconnect_returnsFalse() throws Exception {
        // Register a user, then close the connection (session removed)
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        authenticate(session, 10L);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.sendNotificationToUser("10", "msg")).isFalse();
    }
}
