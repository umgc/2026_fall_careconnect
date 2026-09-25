package com.careconnect.service;

import com.careconnect.model.WebSocketConnection;
import com.careconnect.repository.WebSocketConnectionRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.GoneException;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.PostToConnectionRequest;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.PostToConnectionResponse;

import java.net.URI;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * AWS WebSocket Service for Lambda environment
 * <p>
 * This service manages WebSocket connections through AWS API Gateway
 * when the backend is deployed as Lambda functions.
 * <p>
 * Connection information is persisted in PostgreSQL for durability
 * across Lambda invocations.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.websocket.aws.api-gateway-endpoint")
public class AwsWebSocketService {

    private final WebSocketConnectionRepository connectionRepository;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ConcurrentMap<String, ApiGatewayManagementApiClient> apiClients = new ConcurrentHashMap<>();

    @Value("${careconnect.websocket.aws.api-gateway-endpoint}")
    private String apiGatewayEndpoint;

    @Value("${careconnect.websocket.aws.region:us-east-1}")
    private String awsRegion;

    @Value("${careconnect.websocket.connection-ttl-minutes:120}")
    private int connectionTtlMinutes;

    /**
     * Register a new WebSocket connection
     * Called from Lambda $connect route
     */
    @Transactional
    public void registerConnection(String connectionId, String userEmail, String subscriptionType, Map<String, Object> metadata) {
        try {
            LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(connectionTtlMinutes);

            String metadataJson = metadata != null ? objectMapper.writeValueAsString(metadata) : null;

            WebSocketConnection connection = WebSocketConnection.builder()
                    .connectionId(connectionId)
                    .userEmail(userEmail != null ? userEmail.toLowerCase() : null)
                    .subscriptionType(subscriptionType)
                    .connectionType("aws")
                    .apiGatewayEndpoint(apiGatewayEndpoint)
                    .metadata(metadataJson)
                    .connectedAt(LocalDateTime.now())
                    .lastActivityAt(LocalDateTime.now())
                    .expiresAt(expiresAt)
                    .isActive(true)
                    .build();

            connectionRepository.save(connection);
            log.info("Registered AWS WebSocket connection: {} for {} ({})",
                    connectionId, userEmail, subscriptionType);
        } catch (Exception e) {
            log.error("Failed to register WebSocket connection: {}", connectionId, e);
            throw new RuntimeException("Failed to register WebSocket connection", e);
        }
    }

    /**
     * Deregister a WebSocket connection
     * Called from Lambda $disconnect route
     */
    @Transactional
    public void deregisterConnection(String connectionId) {
        try {
            int updated = connectionRepository.deactivateByConnectionId(connectionId);
            if (updated > 0) {
                log.info("Deregistered AWS WebSocket connection: {}", connectionId);
            } else {
                log.warn("Connection not found for deregistration: {}", connectionId);
            }
        } catch (Exception e) {
            log.error("Failed to deregister WebSocket connection: {}", connectionId, e);
        }
    }

    /**
     * Send message to a specific connection
     */
    public boolean sendMessageToConnection(String connectionId, Map<String, Object> message) {
        try {
            Optional<WebSocketConnection> connectionOpt = connectionRepository.findByConnectionId(connectionId);
            if (connectionOpt.isEmpty()) {
                log.warn("Connection not found: {}", connectionId);
                return false;
            }

            WebSocketConnection connection = connectionOpt.get();
            if (!connection.getIsActive() || connection.isExpired()) {
                log.warn("Connection inactive or expired: {}", connectionId);
                deregisterConnection(connectionId);
                return false;
            }

            // Send message via API Gateway Management API
            return postToConnection(connection, message);
        } catch (Exception e) {
            log.error("Failed to send message to connection {}: {}", connectionId, e.getMessage());
            return false;
        }
    }

    /**
     * Send email verification notification to user's active connection
     */
    public boolean sendEmailVerificationNotification(String email) {
        try {
            Optional<WebSocketConnection> connectionOpt = connectionRepository
                    .findFirstByUserEmailAndSubscriptionTypeAndIsActiveTrueOrderByConnectedAtDesc(
                            email.toLowerCase(),
                            "email-verification"
                    );

            if (connectionOpt.isEmpty()) {
                log.warn("No active email verification connection found for: {}", email);
                return false;
            }

            Map<String, Object> notification = Map.of(
                    "type", "email-verified",
                    "email", email,
                    "verified", true,
                    "message", "Your email has been verified successfully!",
                    "timestamp", System.currentTimeMillis()
            );

            boolean sent = sendMessageToConnection(connectionOpt.get().getConnectionId(), notification);

            // Clean up the connection after sending notification
            if (sent) {
                deregisterConnection(connectionOpt.get().getConnectionId());
            }

            return sent;
        } catch (Exception e) {
            log.error("Failed to send email verification notification to {}: {}", email, e.getMessage());
            return false;
        }
    }

    /**
     * Send message to all active connections for a user
     */
    public int sendMessageToUser(String userEmail, Map<String, Object> message) {
        try {
            List<WebSocketConnection> connections = connectionRepository
                    .findByUserEmailAndIsActiveTrue(userEmail.toLowerCase());

            int sentCount = 0;
            for (WebSocketConnection connection : connections) {
                if (sendMessageToConnection(connection.getConnectionId(), message)) {
                    sentCount++;
                }
            }

            log.info("Sent message to {}/{} connections for user: {}", sentCount, connections.size(), userEmail);
            return sentCount;
        } catch (Exception e) {
            log.error("Failed to send message to user {}: {}", userEmail, e.getMessage());
            return 0;
        }
    }

    /**
     * Update last activity timestamp for a connection
     */
    @Transactional
    public void updateLastActivity(String connectionId) {
        connectionRepository.updateLastActivity(connectionId, LocalDateTime.now());
    }

    /**
     * Clean up expired connections
     */
    @Transactional
    public int cleanupExpiredConnections() {
        try {
            int deactivated = connectionRepository.deactivateExpiredConnections(LocalDateTime.now());
            if (deactivated > 0) {
                log.info("Deactivated {} expired WebSocket connections", deactivated);
            }

            // Delete inactive connections older than 7 days
            LocalDateTime before = LocalDateTime.now().minusDays(7);
            int deleted = connectionRepository.deleteInactiveConnectionsOlderThan(before);
            if (deleted > 0) {
                log.info("Deleted {} old inactive WebSocket connections", deleted);
            }

            return deactivated;
        } catch (Exception e) {
            log.error("Failed to cleanup expired connections", e);
            return 0;
        }
    }

    /**
     * Get active connection count
     */
    public long getActiveConnectionCount() {
        return connectionRepository.countByConnectionTypeAndIsActiveTrue("aws");
    }

    /**
     * Post message to connection via API Gateway Management API
     */
    private boolean postToConnection(WebSocketConnection connection, Map<String, Object> message) {
        try {
            ApiGatewayManagementApiClient client = apiClients.computeIfAbsent(
                    connection.getApiGatewayEndpoint(),
                    endpoint -> ApiGatewayManagementApiClient.builder()
                            .endpointOverride(URI.create(endpoint))
                            .region(Region.of(awsRegion))
                            .credentialsProvider(DefaultCredentialsProvider.create())
                            .build());

            // Convert message to JSON
            String messageJson = objectMapper.writeValueAsString(message);
            SdkBytes data = SdkBytes.fromUtf8String(messageJson);

            // Send message
            PostToConnectionRequest request = PostToConnectionRequest.builder()
                    .connectionId(connection.getConnectionId())
                    .data(data)
                    .build();

            PostToConnectionResponse response = client.postToConnection(request);

            // Update last activity
            updateLastActivity(connection.getConnectionId());

            log.debug("Message sent to connection {}: {}", connection.getConnectionId(), message.get("type"));
            return true;

        } catch (GoneException e) {
            // Connection no longer exists
            log.warn("Connection gone, deregistering: {}", connection.getConnectionId());
            deregisterConnection(connection.getConnectionId());
            return false;
        } catch (Exception e) {
            log.error("Failed to post to connection {}: {}", connection.getConnectionId(), e.getMessage());
            return false;
        }
    }

    @PreDestroy
    public void closeApiClients() {
        apiClients.values().forEach(client -> {
            try {
                client.close();
            } catch (Exception e) {
                log.warn("Error closing API Gateway Management client: {}", e.getMessage());
            }
        });
        apiClients.clear();
    }
}
