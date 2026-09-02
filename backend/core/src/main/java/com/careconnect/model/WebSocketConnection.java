package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * WebSocket connection entity for tracking active WebSocket connections
 * Supports both local WebSocket and AWS API Gateway WebSocket connections
 */
@Entity
@Table(name = "websocket_connections", indexes = {
        @Index(name = "idx_connection_id", columnList = "connection_id"),
        @Index(name = "idx_user_email", columnList = "user_email"),
        @Index(name = "idx_subscription_type", columnList = "subscription_type"),
        @Index(name = "idx_expires_at", columnList = "expires_at")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WebSocketConnection {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Connection ID - For AWS API Gateway, this is the connectionId
     * For local WebSocket, this is the session ID
     */
    @Column(name = "connection_id", nullable = false, unique = true, length = 128)
    private String connectionId;

    /**
     * User email associated with this connection
     * May be null for unauthenticated connections (e.g., email verification)
     */
    @Column(name = "user_email", length = 255)
    private String userEmail;

    /**
     * User ID if authenticated
     */
    @Column(name = "user_id")
    private Long userId;

    /**
     * Type of subscription:
     * - "email-verification": Waiting for email verification
     * - "authenticated": Full authenticated connection
     * - "notifications": Notification-only connection
     */
    @Column(name = "subscription_type", nullable = false, length = 50)
    private String subscriptionType;

    /**
     * Connection type: "aws" for AWS API Gateway, "local" for Spring WebSocket
     */
    @Column(name = "connection_type", nullable = false, length = 20)
    @Builder.Default
    private String connectionType = "local";

    /**
     * API Gateway endpoint URL (for AWS connections only)
     */
    @Column(name = "api_gateway_endpoint", length = 512)
    private String apiGatewayEndpoint;

    /**
     * Additional metadata in JSON format
     */
    @Column(name = "metadata", columnDefinition = "TEXT")
    private String metadata;

    /**
     * When the connection was established
     */
    @Column(name = "connected_at", nullable = false)
    @Builder.Default
    private LocalDateTime connectedAt = LocalDateTime.now();

    /**
     * Last activity timestamp
     */
    @Column(name = "last_activity_at")
    @Builder.Default
    private LocalDateTime lastActivityAt = LocalDateTime.now();

    /**
     * When the connection expires (for cleanup)
     */
    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    /**
     * Whether the connection is active
     */
    @Column(name = "is_active", nullable = false)
    @Builder.Default
    private Boolean isActive = true;

    /**
     * Update last activity timestamp
     */
    public void updateLastActivity() {
        this.lastActivityAt = LocalDateTime.now();
    }

    /**
     * Check if connection has expired
     */
    public boolean isExpired() {
        return LocalDateTime.now().isAfter(expiresAt);
    }

    /**
     * Mark connection as inactive
     */
    public void deactivate() {
        this.isActive = false;
    }
}
