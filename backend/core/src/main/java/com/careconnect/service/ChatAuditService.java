package com.careconnect.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;

/**
 * Service for audit logging of chat interactions
 * <p>
 * Privacy Policy: Only metadata is logged - no conversation content,
 * personal information, or health data is stored in audit logs.
 * <p>
 * Audit logs contain:
 * - Timestamp
 * - User ID (hashed/anonymized)
 * - Session ID
 * - Action type (chat_started, message_sent, conversation_deleted, etc.)
 * - Session duration
 * - System performance metrics
 * - Error codes (if any)
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ChatAuditService {

    // Salt for user ID hashing - in production, this should be loaded from secure configuration
    private static final String USER_ID_SALT = "CareConnect_UserAudit_Salt_2024";

    /**
     * Log chat session start
     */
    public void logChatSessionStart(Long userId, String sessionId, String userAgent, String ipAddress) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("CHAT_SESSION_STARTED")
                .metadata(Map.of(
                        "user_agent", sanitizeUserAgent(userAgent),
                        "ip_address", anonymizeIpAddress(ipAddress),
                        "session_type", "ai_chat"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Log message sent (metadata only)
     */
    public void logMessageSent(Long userId, String sessionId, int messageLength, long responseTimeMs) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("MESSAGE_SENT")
                .metadata(Map.of(
                        "message_length", messageLength,
                        "response_time_ms", responseTimeMs,
                        "message_type", "user_to_ai"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Log AI response (metadata only)
     */
    public void logAiResponse(Long userId, String sessionId, int responseLength, long processingTimeMs) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("AI_RESPONSE_GENERATED")
                .metadata(Map.of(
                        "response_length", responseLength,
                        "processing_time_ms", processingTimeMs,
                        "response_type", "ai_to_user"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Log conversation deletion
     */
    public void logConversationDeleted(Long userId, String sessionId, String deletionReason) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("CONVERSATION_DELETED")
                .metadata(Map.of(
                        "deletion_reason", deletionReason,
                        "deletion_type", "user_initiated"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Log conversation shared with provider
     */
    public void logConversationShared(Long userId, String sessionId, Long providerId) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("CONVERSATION_SHARED")
                .metadata(Map.of(
                        "provider_id", hashUserId(providerId),
                        "share_type", "user_consent"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Log session timeout
     */
    public void logSessionTimeout(Long userId, String sessionId, int sessionDurationMinutes) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("SESSION_TIMEOUT")
                .metadata(Map.of(
                        "session_duration_minutes", sessionDurationMinutes,
                        "timeout_reason", "inactivity"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Log system error
     */
    public void logSystemError(Long userId, String sessionId, String errorCode, String errorType) {
        AuditLogEntry entry = AuditLogEntry.builder()
                .logId(UUID.randomUUID().toString())
                .timestamp(LocalDateTime.now())
                .userId(hashUserId(userId))
                .sessionId(sessionId)
                .action("SYSTEM_ERROR")
                .metadata(Map.of(
                        "error_code", errorCode,
                        "error_type", errorType,
                        "severity", "error"
                ))
                .build();

        logAuditEntry(entry);
    }

    /**
     * Hash user ID for privacy using SHA-256 with salt
     */
    private String hashUserId(Long userId) {
        if (userId == null) return "anonymous";

        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");

            // Combine userId with salt
            String input = userId.toString() + USER_ID_SALT;
            byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));

            // Convert to base64 for storage
            String hashedId = Base64.getEncoder().encodeToString(hash);

            // Take first 12 characters for readability while maintaining uniqueness
            return "user_" + hashedId.substring(0, 12);

        } catch (Exception e) {
            log.error("Error hashing user ID: {}", e.getMessage());
            // Fallback to secure random prefix if hashing fails
            return "user_" + UUID.randomUUID().toString().substring(0, 8);
        }
    }

    /**
     * Sanitize user agent string
     */
    private String sanitizeUserAgent(String userAgent) {
        if (userAgent == null) return "unknown";
        // Remove potentially identifying information
        return userAgent.length() > 100 ? userAgent.substring(0, 100) : userAgent;
    }

    /**
     * Anonymize IP address
     */
    private String anonymizeIpAddress(String ipAddress) {
        if (ipAddress == null) return "unknown";
        // Remove last octet for IPv4 or last segment for IPv6
        if (ipAddress.contains(".")) {
            String[] parts = ipAddress.split("\\.");
            if (parts.length == 4) {
                return parts[0] + "." + parts[1] + "." + parts[2] + ".xxx";
            }
        }
        return "anonymized";
    }

    /**
     * Log audit entry (in production, this would write to secure audit log)
     */
    private void logAuditEntry(AuditLogEntry entry) {
        // In production, this would write to a secure, tamper-proof audit log
        // For now, using structured logging
        log.info("AUDIT: {} | User: {} | Session: {} | Action: {} | Metadata: {}",
                entry.getTimestamp(),
                entry.getUserId(),
                entry.getSessionId(),
                entry.getAction(),
                entry.getMetadata());
    }

    /**
     * Audit log entry model
     */
    @lombok.Builder
    @lombok.Data
    public static class AuditLogEntry {
        private String logId;
        private LocalDateTime timestamp;
        private String userId; // Hashed/anonymized
        private String sessionId;
        private String action;
        private Map<String, Object> metadata;
    }
}
