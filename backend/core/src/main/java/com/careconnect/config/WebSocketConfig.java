package com.careconnect.config;

import com.careconnect.websocket.CallNotificationHandler;
import com.careconnect.websocket.CareConnectWebSocketHandler;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import com.careconnect.websocket.NotificationWebSocketHandler;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * WebSocket Configuration
 * <p>
 * This configuration is profile-aware:
 * - Local Development (dev profile): Enables Spring WebSocket for real-time connections
 * - Production (prod profile): Disabled - Uses AWS API Gateway WebSocket instead
 * <p>
 * Configuration is controlled by:
 * - careconnect.websocket.enabled: Enable/disable WebSocket support
 * - careconnect.websocket.mode: "local" for Spring WebSocket, "aws" for API Gateway
 */
@Slf4j
@Configuration
@ConditionalOnProperty(name = "careconnect.websocket.enabled", havingValue = "true", matchIfMissing = true)
@ConditionalOnExpression("'${careconnect.websocket.mode:aws}' == 'local'")
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    @Autowired
    private CallNotificationHandler callNotificationHandler;

    @Autowired
    private CareConnectWebSocketHandler careConnectWebSocketHandler;

    @Autowired
    private NotificationWebSocketHandler notificationWebSocketHandler;

    @Autowired
    private ChatMessageWebSocketHandler chatMessageWebSocketHandler;

    @Value("${careconnect.websocket.endpoint:/ws/careconnect}")
    private String careConnectEndpoint;

    @Value("${careconnect.websocket.allowed-origins:*}")
    private String allowedOrigins;

    private String[] allowedOriginPatterns() {
        return java.util.Arrays.stream(allowedOrigins.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toArray(String[]::new);
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        log.info("Registering WebSocket handlers for local development mode");
        log.info("CareConnect WebSocket endpoint: {}", careConnectEndpoint);
        log.info("Allowed origins: {}", allowedOrigins);

        String[] originPatterns = allowedOriginPatterns();

        // Call/SMS notification WebSocket endpoint
        registry.addHandler(callNotificationHandler, "/ws/calls-ws")
                .setAllowedOriginPatterns(originPatterns);

        registry.addHandler(callNotificationHandler, "/ws/calls")
                .setAllowedOriginPatterns(originPatterns)
                .withSockJS();

        // General CareConnect WebSocket endpoint for real-time updates
        registry.addHandler(careConnectWebSocketHandler, careConnectEndpoint)
                .setAllowedOriginPatterns(originPatterns)
                .withSockJS();

        // Notification WebSocket endpoint (no SockJS fallback)
        registry.addHandler(notificationWebSocketHandler, "/ws/notifications")
                .setAllowedOriginPatterns(originPatterns);

        // Person-to-Person Chat — native WebSocket (no SockJS, Flutter uses ws:// directly)
        registry.addHandler(chatMessageWebSocketHandler, "/ws/chat")
                .setAllowedOriginPatterns(originPatterns);

        log.info("WebSocket handlers registered successfully in LOCAL mode");
    }
}
