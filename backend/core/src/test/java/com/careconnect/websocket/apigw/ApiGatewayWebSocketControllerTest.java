package com.careconnect.websocket.apigw;

import com.careconnect.websocket.CallNotificationHandler;
import com.careconnect.websocket.CareConnectWebSocketHandler;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import com.careconnect.websocket.NotificationWebSocketHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketMessage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

/**
 * Unit tests for {@link ApiGatewayWebSocketController}.
 *
 * <p>The four Spring handlers and the connection client are mocked, and a real
 * {@link ApiGatewaySessionRegistry} is used, so each test checks the routing decision: which
 * handler callback runs, in what order, and what status API Gateway receives.
 */
@ExtendWith(MockitoExtension.class)
class ApiGatewayWebSocketControllerTest {

    @Mock
    private ApiGatewayConnectionClient client;
    @Mock
    private CallNotificationHandler callHandler;
    @Mock
    private CareConnectWebSocketHandler careConnectHandler;
    @Mock
    private NotificationWebSocketHandler notificationHandler;
    @Mock
    private ChatMessageWebSocketHandler chatHandler;

    private ApiGatewaySessionRegistry registry;
    private ApiGatewayWebSocketController controller;

    @BeforeEach
    void setUp() {
        registry = new ApiGatewaySessionRegistry();
        controller = new ApiGatewayWebSocketController(
                registry, client, callHandler, careConnectHandler, notificationHandler, chatHandler);
    }

    // ─── connect ─────────────────────────────────────────────────────────────

    @Test
    void connect_knownChannel_registersSessionWithoutCallingHandler() {
        var response = controller.connect("c1", "chat");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(registry.get("c1").getChannel()).isEqualTo(WebSocketChannel.CHAT);
        // Nothing can be pushed until $connect returns, so the handler is not told yet.
        verifyNoInteractions(chatHandler);
    }

    @Test
    void connect_unknownOrMissingChannel_refusesConnection() {
        assertThat(controller.connect("c1", "admin").getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(controller.connect("c2", null).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(registry.size()).isZero();
    }

    // ─── message ─────────────────────────────────────────────────────────────

    @Test
    void message_firstMessage_establishesThenDispatchesToChannelHandler() throws Exception {
        // Arrange
        controller.connect("c1", "calls");

        // Act
        var response = controller.message("c1", "{\"type\":\"authenticate\",\"token\":\"t\"}");

        // Assert: connect callback first, then the message, both on the calls handler only
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        var session = registry.get("c1");
        var inOrder = org.mockito.Mockito.inOrder(callHandler);
        inOrder.verify(callHandler).afterConnectionEstablished(session);
        ArgumentCaptor<WebSocketMessage<?>> captor = ArgumentCaptor.forClass(WebSocketMessage.class);
        inOrder.verify(callHandler).handleMessage(eq(session), captor.capture());
        assertThat(((TextMessage) captor.getValue()).getPayload()).contains("authenticate");
        verifyNoInteractions(careConnectHandler, notificationHandler, chatHandler);
    }

    @Test
    void message_laterMessages_doNotReEstablish() throws Exception {
        controller.connect("c1", "notifications");

        controller.message("c1", "{\"type\":\"authenticate\"}");
        controller.message("c1", "hello");

        var session = registry.get("c1");
        verify(notificationHandler, times(1)).afterConnectionEstablished(session);
        verify(notificationHandler, times(2)).handleMessage(eq(session), any());
    }

    @Test
    void message_eachChannelRoutesToItsHandler() throws Exception {
        controller.connect("a", "careconnect");
        controller.connect("b", "chat");

        controller.message("a", "{\"type\":\"subscribe-to-updates\"}");
        controller.message("b", "{\"type\":\"typing\"}");

        verify(careConnectHandler).handleMessage(eq(registry.get("a")), any());
        verify(chatHandler).handleMessage(eq(registry.get("b")), any());
        verifyNoInteractions(callHandler, notificationHandler);
    }

    /**
     * Heartbeats only reset API Gateway's idle timer; they must not reach handlers (chat would answer
     * an unknown type with an error).
     */
    @Test
    void message_heartbeatAndBlankBodies_areAcknowledgedWithoutDispatch() {
        controller.connect("c1", "chat");

        assertThat(controller.message("c1", "{\"type\":\"heartbeat\"}").getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(controller.message("c1", "  ").getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(controller.message("c1", null).getStatusCode()).isEqualTo(HttpStatus.OK);

        verifyNoInteractions(chatHandler);
    }

    @Test
    void message_nonJsonBody_isDispatchedNotTreatedAsHeartbeat() throws Exception {
        controller.connect("c1", "notifications");

        controller.message("c1", "plain text");

        verify(notificationHandler).handleMessage(eq(registry.get("c1")), any());
    }

    /**
     * After a task restart API Gateway still holds sockets this task never saw. Closing them forces
     * the client to reconnect and re-authenticate here.
     */
    @Test
    void message_unknownConnection_deletesItAndReturnsGone() {
        var response = controller.message("stale", "{\"type\":\"authenticate\"}");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.GONE);
        verify(client).delete("stale");
        verifyNoInteractions(callHandler, careConnectHandler, notificationHandler, chatHandler);
    }

    @Test
    void message_handlerThrows_returns500() throws Exception {
        controller.connect("c1", "calls");
        doThrow(new IllegalStateException("boom")).when(callHandler).handleMessage(any(), any());

        var response = controller.message("c1", "{\"type\":\"authenticate\"}");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── disconnect ──────────────────────────────────────────────────────────

    @Test
    void disconnect_knownConnection_closesSessionAndNotifiesHandler() throws Exception {
        controller.connect("c1", "chat");
        var session = registry.get("c1");

        var response = controller.disconnect("c1");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(session.isOpen()).isFalse();
        assertThat(registry.get("c1")).isNull();
        verify(chatHandler).afterConnectionClosed(session, CloseStatus.NORMAL);
        // The client is already gone; the backend must not try to delete it again.
        verify(client, never()).delete(any());
    }

    @Test
    void disconnect_unknownConnection_isIgnored() {
        assertThat(controller.disconnect("nope").getStatusCode()).isEqualTo(HttpStatus.OK);
        verifyNoInteractions(callHandler, careConnectHandler, notificationHandler, chatHandler);
    }

    @Test
    void disconnect_handlerThrows_stillReturnsOk() throws Exception {
        controller.connect("c1", "calls");
        doThrow(new IllegalStateException("boom")).when(callHandler).afterConnectionClosed(any(), any());

        assertThat(controller.disconnect("c1").getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(registry.get("c1")).isNull();
    }
}
