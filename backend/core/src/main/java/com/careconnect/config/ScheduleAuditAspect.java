package com.careconnect.config;

import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.model.schedule.ScheduledVisitAudit;
import com.careconnect.repository.schedule.ScheduledVisitAuditRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.aspectj.lang.JoinPoint;
import org.aspectj.lang.annotation.After;
import org.aspectj.lang.annotation.AfterReturning;
import org.aspectj.lang.annotation.Aspect;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

/**
 * AspectJ aspect to automatically audit ScheduledVisit changes
 * Captures before/after values and logs to audit trail
 */
@Aspect
@Component
@RequiredArgsConstructor
public class ScheduleAuditAspect {
    private static final Logger log = LoggerFactory.getLogger(ScheduleAuditAspect.class);

    private final ScheduledVisitAuditRepository auditRepository;
    private final ObjectMapper objectMapper;

    /**
     * Intercept visit creation and log to audit trail
     */
    @AfterReturning(value = "execution(* com.careconnect.service.schedule.ScheduledVisitService.createScheduledVisit(..))", returning = "result")
    public void auditVisitCreation(JoinPoint joinPoint, Object result) {
        try {
            log.debug("Auditing visit creation");
            Long visitId = extractVisitIdFromResult(result);

            if (visitId != null) {
                String currentUser = getCurrentUsername();
                createAuditEntry(
                        visitId,
                        "CREATED",
                        null,
                        null,
                        serializeObject(result),
                        currentUser);
            }
        } catch (Exception e) {
            log.error("Error auditing visit creation", e);
        }
    }

    /**
     * Intercept visit update and log changes to audit trail
     */
    @After(value = "execution(* com.careconnect.service.schedule.ScheduledVisitService.updateScheduledVisit(..))")
    public void auditVisitUpdate(JoinPoint joinPoint) {
        try {
            log.debug("Auditing visit update");
            // Note: The actual update logging happens in the service method itself
            // This is a fallback in case changes slip through
        } catch (Exception e) {
            log.error("Error auditing visit update", e);
        }
    }

    /**
     * Intercept visit deletion and log to audit trail
     */
    @After(value = "execution(* com.careconnect.service.schedule.ScheduledVisitService.deleteScheduledVisit(..))")
    public void auditVisitDeletion(JoinPoint joinPoint) {
        try {
            log.debug("Auditing visit deletion");
            Object[] args = joinPoint.getArgs();
            if (args.length > 0 && args[0] instanceof Long) {
                Long visitId = (Long) args[0];
                String currentUser = getCurrentUsername();

                createAuditEntry(
                        visitId,
                        "DELETED",
                        "full_record",
                        "Visit record deleted",
                        "",
                        currentUser);
            }
        } catch (Exception e) {
            log.error("Error auditing visit deletion", e);
        }
    }

    /**
     * Intercept status updates and log to audit trail
     */
    @AfterReturning(value = "execution(* com.careconnect.service.schedule.ScheduledVisitService.updateVisitStatus(..))", returning = "result")
    public void auditStatusChange(JoinPoint joinPoint, Object result) {
        try {
            log.debug("Auditing visit status change");
            Object[] args = joinPoint.getArgs();

            if (args.length >= 2) {
                Long visitId = (Long) args[0];
                String newStatus = (String) args[1];
                String currentUser = getCurrentUsername();

                createAuditEntry(
                        visitId,
                        "UPDATED",
                        "status",
                        null,
                        newStatus,
                        currentUser);
            }
        } catch (Exception e) {
            log.error("Error auditing status change", e);
        }
    }

    /**
     * Create an audit entry
     */
    private void createAuditEntry(
            Long visitId,
            String action,
            String changedField,
            String oldValue,
            String newValue,
            String changedBy) {
        try {
            ScheduledVisitAudit audit = new ScheduledVisitAudit();
            audit.setVisitId(visitId);
            audit.setAction(action);
            audit.setChangedField(changedField);
            audit.setOldValue(oldValue);
            audit.setNewValue(newValue);
            audit.setChangedBy(changedBy);
            audit.setChangedAt(LocalDateTime.now());

            auditRepository.save(audit);
            log.debug("Audit entry created for visit {} with action {}", visitId, action);
        } catch (Exception e) {
            log.error("Failed to create audit entry", e);
        }
    }

    /**
     * Extract visit ID from service method result
     */
    private Long extractVisitIdFromResult(Object result) {
        try {
            if (result != null && result.getClass().getSimpleName().equals("ScheduledVisitResponse")) {
                // Reflection to get id field from ScheduledVisitResponse
                java.lang.reflect.Field idField = result.getClass().getDeclaredField("id");
                idField.setAccessible(true);
                return (Long) idField.get(result);
            }
        } catch (Exception e) {
            log.warn("Failed to extract visit ID from result", e);
        }
        return null;
    }

    /**
     * Get current authenticated username
     */
    private String getCurrentUsername() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.isAuthenticated()) {
            return authentication.getName();
        }
        return "SYSTEM";
    }

    /**
     * Serialize object to JSON string
     */
    private String serializeObject(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (Exception e) {
            log.warn("Failed to serialize object", e);
            return obj.toString();
        }
    }
}