package com.careconnect.websocket.apigw;

import com.careconnect.websocket.CallNotificationHandler;
import com.careconnect.websocket.CareConnectWebSocketHandler;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import com.careconnect.websocket.NotificationWebSocketHandler;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.EnumMap;
import java.util.Map;
import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketHandler;

/**
 * Receives the API Gateway WebSocket API's route integrations and drives the Spring handlers.
 *
 * <p>API Gateway turns each {@code $connect}, message, and {@code $disconnect} into a POST here
 * with the connection id in {@value #CONNECTION_HEADER}. Only reachable on the internal port (see
 * {@link InternalPortFilter}).
 *
 * <p>The handler's connect callback runs on the first message rather than on {@code $connect}:
 * API Gateway does not open the connection until this endpoint returns, so nothing can be pushed
 * to the client before then.
 */
@Slf4j
@RestController
@RequestMapping("/api/internal/ws")
@ConditionalOnExpression(ApiGatewayWebSocketConfig.ENABLED)
public class ApiGatewayWebSocketController {

    static final String CONNECTION_HEADER = "X-Ws-Connection-Id";
    static final String CHANNEL_HEADER = "X-Ws-Channel";

    private final ApiGatewaySessionRegistry registry;
    private final ApiGatewayConnectionClient client;
    private final Map<WebSocketChannel, WebSocketHandler> handlers = new EnumMap<>(WebSocketChannel.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    public ApiGatewayWebSocketController(
            final ApiGatewaySessionRegistry registry,
            final ApiGatewayConnectionClient client,
            final CallNotificationHandler callNotificationHandler,
            final CareConnectWebSocketHandler careConnectWebSocketHandler,
            final NotificationWebSocketHandler notificationWebSocketHandler,
            final ChatMessageWebSocketHandler chatMessageWebSocketHandler) {
        this.registry = registry;
        this.client = client;
        handlers.put(WebSocketChannel.CALLS, callNotificationHandler);
        handlers.put(WebSocketChannel.CARECONNECT, careConnectWebSocketHandler);
        handlers.put(WebSocketChannel.NOTIFICATIONS, notificationWebSocketHandler);
        handlers.put(WebSocketChannel.CHAT, chatMessageWebSocketHandler);
    }

    /** {@code $connect}: accept the connection only for a known channel (400 refuses it). */
    @PostMapping("/connect")
    public ResponseEntity<Void> connect(
            @RequestHeader(CONNECTION_HEADER) final String connectionId,
            @RequestHeader(value = CHANNEL_HEADER, required = false) final String channelValue) {
        final Optional<WebSocketChannel> channel = WebSocketChannel.fromQueryValue(channelValue);
        if (channel.isEmpty()) {
            log.warn("Refusing websocket connection {}: unknown channel", connectionId);
            return ResponseEntity.badRequest().build();
        }
        registry.register(new ApiGatewayWebSocketSession(connectionId, channel.get(), client));
        return ResponseEntity.ok().build();
    }

    /** {@code $default}: hand a client message to the channel's handler. */
    @PostMapping("/message")
    public ResponseEntity<Void> message(
            @RequestHeader(CONNECTION_HEADER) final String connectionId,
            @RequestBody(required = false) final String body) {
        final ApiGatewayWebSocketSession session = registry.get(connectionId);
        if (session == null) {
            // Unknown here (e.g. the task restarted while API Gateway kept the socket open). Close
            // it so the client reconnects and re-authenticates against this task.
            log.info("Closing unknown websocket connection {}", connectionId);
            client.delete(connectionId);
            return ResponseEntity.status(HttpStatus.GONE).build();
        }
        if (body == null || body.isBlank() || isHeartbeat(body)) {
            // Heartbeats only exist to reset API Gateway's 10-minute idle timeout.
            return ResponseEntity.ok().build();
        }
        final WebSocketHandler handler = handlers.get(session.getChannel());
        try {
            if (session.markEstablished()) {
                handler.afterConnectionEstablished(session);
            }
            handler.handleMessage(session, new TextMessage(body));
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Websocket handler failed for connection {} on {}", connectionId, session.getChannel(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    /** {@code $disconnect} (best-effort): let the handler drop its user mapping. */
    @PostMapping("/disconnect")
    public ResponseEntity<Void> disconnect(@RequestHeader(CONNECTION_HEADER) final String connectionId) {
        final ApiGatewayWebSocketSession session = registry.remove(connectionId);
        if (session == null) {
            return ResponseEntity.ok().build();
        }
        session.markClosed();
        try {
            handlers.get(session.getChannel()).afterConnectionClosed(session, CloseStatus.NORMAL);
        } catch (Exception e) {
            log.warn("Websocket close callback failed for connection {}", connectionId, e);
        }
        return ResponseEntity.ok().build();
    }

    private boolean isHeartbeat(final String body) {
        try {
            final JsonNode node = objectMapper.readTree(body);
            return node != null && "heartbeat".equals(node.path("type").asText(null));
        } catch (JsonProcessingException e) {
            return false;
        }
    }
}
