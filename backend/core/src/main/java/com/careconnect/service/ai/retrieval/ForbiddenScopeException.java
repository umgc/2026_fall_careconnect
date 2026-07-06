package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;

import java.util.UUID;

/**
 * Thrown when Ask AI retrieval scope cannot be granted for the caller and patient (FR-AI-1).
 * Maps to HTTP 403 with code {@code FORBIDDEN_SCOPE} and {@code deliveryStatus: WITHHELD}.
 */
public class ForbiddenScopeException extends Exception {

    public static final String ERROR_CODE = "FORBIDDEN_SCOPE";

    private final ScopeDenialReason denialReason;
    private final Long patientId;
    private final Long callerUserId;
    private final UUID auditId;

    public ForbiddenScopeException(
            ScopeDenialReason denialReason,
            Long patientId,
            Long callerUserId,
            String message,
            UUID auditId) {
        super(message);
        this.denialReason = denialReason;
        this.patientId = patientId;
        this.callerUserId = callerUserId;
        this.auditId = auditId;
    }

    public static ForbiddenScopeException of(
            ScopeDenialReason denialReason,
            Long patientId,
            Long callerUserId,
            String message,
            UUID auditId) {
        return new ForbiddenScopeException(denialReason, patientId, callerUserId, message, auditId);
    }

    public static ForbiddenScopeException patientOutOfScope(
            Long patientId,
            String callerEmail,
            Long callerUserId,
            UUID auditId) {
        return of(
                ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                patientId,
                callerUserId,
                String.format("Patient %d is out of scope for user '%s'", patientId, callerEmail),
                auditId);
    }

    public static ForbiddenScopeException patientNotFound(Long patientId, Long callerUserId, UUID auditId) {
        return of(
                ScopeDenialReason.PATIENT_NOT_FOUND,
                patientId,
                callerUserId,
                String.format("Patient %d not found", patientId),
                auditId);
    }

    public static ForbiddenScopeException noPermittedSourceTypes(Long patientId, Long callerUserId, UUID auditId) {
        return of(
                ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES,
                patientId,
                callerUserId,
                String.format(
                        "No permitted source types remain for patient %d after RBAC and consent filters",
                        patientId),
                auditId);
    }

    public static ForbiddenScopeException unsupportedRole(Role callerRole, Long callerUserId, UUID auditId) {
        return of(
                ScopeDenialReason.UNSUPPORTED_ROLE,
                null,
                callerUserId,
                String.format("Role '%s' cannot resolve Ask AI retrieval scope", callerRole),
                auditId);
    }

    public String getErrorCode() {
        return ERROR_CODE;
    }

    public ScopeDenialReason getDenialReason() {
        return denialReason;
    }

    public Long getPatientId() {
        return patientId;
    }

    public Long getCallerUserId() {
        return callerUserId;
    }

    public UUID getAuditId() {
        return auditId;
    }
}
