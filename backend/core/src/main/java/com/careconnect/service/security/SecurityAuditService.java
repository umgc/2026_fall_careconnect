package com.careconnect.service.security;

import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.LocalDateTime;

@Service
public class SecurityAuditService {
    private static final Logger log = LoggerFactory.getLogger(SecurityAuditService.class);

    public void logSanitizationAction(Long userId, String conversationId, String actionType, String details) {
        log.warn("SECURITY_AUDIT - Sanitization Action: userId={}, conversationId={}, action={}, details={}, timestamp={}",
                userId, conversationId, actionType, details, LocalDateTime.now());
    }

    public void logSecurityViolation(Long userId, String conversationId, String violationType, String details) {
        log.error("SECURITY_VIOLATION - userId={}, conversationId={}, violation={}, details={}, timestamp={}",
                userId, conversationId, violationType, details, LocalDateTime.now());
    }

    public void logGovernanceAction(Long userId, String conversationId, String actionType, String details) {
        log.info("AI_GOVERNANCE - userId={}, conversationId={}, action={}, details={}, timestamp={}",
                userId, conversationId, actionType, details, LocalDateTime.now());
    }

    public void logConfigurationValidationError(String service, String configType, String details) {
        log.error("CONFIG_VALIDATION_ERROR - service={}, configType={}, details={}, timestamp={}",
                service, configType, details, LocalDateTime.now());
    }
}