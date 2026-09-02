package com.careconnect.websocket;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class NotificationWebSocketHandlerTest {

    @Mock
    WebSocketSession session;

    private NotificationWebSocketHandler handler;

    @BeforeEach
    void setUp() throws Exception {
        handler = new NotificationWebSocketHandler();
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

    // ─── handleTextMessage() — REGISTER_USER branch ──────────────────────────

    @Test
    void handleTextMessage_registerUser_storesMappingAndSendsResponse() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:user42"));

        verify(session).sendMessage(any(TextMessage.class));
        // Registration now makes the user reachable
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.sendNotificationToUser("user42", "hello")).isTrue();
    }

    // ─── handleTextMessage() — echo branch ───────────────────────────────────

    @Test
    void handleTextMessage_nonRegisterPayload_echoesMessage() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        handler.handleTextMessage(session, new TextMessage("Hello there"));

        verify(session).sendMessage(any(TextMessage.class));
    }

    // ─── afterConnectionClosed() ─────────────────────────────────────────────

    @Test
    void afterConnectionClosed_removesSessionAndUserMapping() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:userX"));

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        // After close the user entry is gone → sendNotificationToUser returns false
        assertThat(handler.sendNotificationToUser("userX", "msg")).isFalse();
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

    // ─── sendNotificationToUser() ────────────────────────────────────────────

    @Test
    void sendNotificationToUser_unknownUser_returnsFalse() throws Exception {
        assertThat(handler.sendNotificationToUser("nobody", "msg")).isFalse();
    }

    @Test
    void sendNotificationToUser_sessionClosed_returnsFalse() throws Exception {
        when(session.getId()).thenReturn("s1");
        // Open for the REGISTER_USER response, closed afterwards
        when(session.isOpen()).thenReturn(true);
        handler.afterConnectionEstablished(session);
        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:userY"));

        when(session.isOpen()).thenReturn(false);

        assertThat(handler.sendNotificationToUser("userY", "msg")).isFalse();
    }

    @Test
    void sendNotificationToUser_sendThrows_returnsFalse() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(session.isOpen()).thenReturn(true);
        // First call (REGISTER_USER response) succeeds; second (notification) throws
        doNothing()
                .doThrow(new RuntimeException("send fail"))
                .when(session).sendMessage(any());
        handler.afterConnectionEstablished(session);
        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:userZ"));

        assertThat(handler.sendNotificationToUser("userZ", "msg")).isFalse();
    }

    // ─── sendNotificationToAll() — multiple sessions ─────────────────────────

    @Test
    void sendNotificationToAll_multipleSessions_sendsToAllOpen() throws Exception {
        @SuppressWarnings("unchecked")
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
        @SuppressWarnings("unchecked")
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

    // ─── handleTextMessage() — verify message content ────────────────────────

    @Test
    void handleTextMessage_registerUser_responsContainsUserId() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:user99"));

        org.mockito.ArgumentCaptor<TextMessage> captor =
                org.mockito.ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertThat(captor.getValue().getPayload()).contains("user99");
    }

    @Test
    void handleTextMessage_echoMessage_responseContainsEchoPrefix() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);

        handler.handleTextMessage(session, new TextMessage("Hello world"));

        org.mockito.ArgumentCaptor<TextMessage> captor =
                org.mockito.ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertThat(captor.getValue().getPayload()).startsWith("Echo: ");
        assertThat(captor.getValue().getPayload()).contains("Hello world");
    }

    // ─── sendNotificationToUser — session exists but closed ──────────────────

    @Test
    void sendNotificationToUser_sessionExistsButNull_returnsFalse() throws Exception {
        // Register a user, then close the connection (session removed)
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        handler.handleTextMessage(session, new TextMessage("REGISTER_USER:userA"));

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.sendNotificationToUser("userA", "msg")).isFalse();
    }
}
