package com.careconnect.repository;

import com.careconnect.model.WebSocketConnection;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface WebSocketConnectionRepository extends JpaRepository<WebSocketConnection, Long> {

    /**
     * Find connection by connection ID
     */
    Optional<WebSocketConnection> findByConnectionId(String connectionId);

    /**
     * Find all active connections for a user email
     */
    List<WebSocketConnection> findByUserEmailAndIsActiveTrue(String userEmail);

    /**
     * Find all active connections for a user ID
     */
    List<WebSocketConnection> findByUserIdAndIsActiveTrue(Long userId);

    /**
     * Find active connection by subscription type and email
     * Used for email verification subscriptions
     */
    Optional<WebSocketConnection> findFirstByUserEmailAndSubscriptionTypeAndIsActiveTrueOrderByConnectedAtDesc(
            String userEmail,
            String subscriptionType
    );

    /**
     * Find all active connections by subscription type
     */
    List<WebSocketConnection> findBySubscriptionTypeAndIsActiveTrue(String subscriptionType);

    /**
     * Find all expired connections
     */
    @Query("SELECT w FROM WebSocketConnection w WHERE w.expiresAt < :now AND w.isActive = true")
    List<WebSocketConnection> findExpiredConnections(@Param("now") LocalDateTime now);

    /**
     * Deactivate connection by connection ID
     */
    @Modifying
    @Query("UPDATE WebSocketConnection w SET w.isActive = false WHERE w.connectionId = :connectionId")
    int deactivateByConnectionId(@Param("connectionId") String connectionId);

    /**
     * Deactivate all connections for a user
     */
    @Modifying
    @Query("UPDATE WebSocketConnection w SET w.isActive = false WHERE w.userEmail = :userEmail")
    int deactivateByUserEmail(@Param("userEmail") String userEmail);

    /**
     * Deactivate all expired connections
     */
    @Modifying
    @Query("UPDATE WebSocketConnection w SET w.isActive = false WHERE w.expiresAt < :now AND w.isActive = true")
    int deactivateExpiredConnections(@Param("now") LocalDateTime now);

    /**
     * Delete inactive connections older than specified time
     */
    @Modifying
    @Query("DELETE FROM WebSocketConnection w WHERE w.isActive = false AND w.connectedAt < :before")
    int deleteInactiveConnectionsOlderThan(@Param("before") LocalDateTime before);

    /**
     * Count active connections
     */
    long countByIsActiveTrue();

    /**
     * Count active connections by type
     */
    long countByConnectionTypeAndIsActiveTrue(String connectionType);

    /**
     * Update last activity timestamp
     */
    @Modifying
    @Query("UPDATE WebSocketConnection w SET w.lastActivityAt = :timestamp WHERE w.connectionId = :connectionId")
    int updateLastActivity(@Param("connectionId") String connectionId, @Param("timestamp") LocalDateTime timestamp);
}