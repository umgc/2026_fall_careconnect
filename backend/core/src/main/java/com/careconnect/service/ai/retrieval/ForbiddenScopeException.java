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
    private final UUID requestId;
    private final UUID auditId;
    private final UUID sessionId;

    private ForbiddenScopeException(
            ScopeDenialReason denialReason,
            Long patientId,
            Long callerUserId,
            String message,
            UUID requestId,
            UUID auditId,
            UUID sessionId) {
        super(message);
        this.denialReason = denialReason;
        this.patientId = patientId;
        this.callerUserId = callerUserId;
        this.requestId = requestId;
        this.auditId = auditId;
        this.sessionId = sessionId;
    }

    public static ForbiddenScopeException of(
            ScopeDenialReason denialReason,
            Long patientId,
            Long callerUserId,
            String detail,
            UUID auditId) {
        return new ForbiddenScopeException(
                denialReason, patientId, callerUserId, detail, null, auditId, null);
    }

    public static ForbiddenScopeException unsupportedRole(Role callerRole, Long callerUserId, String detail, UUID auditId) {
        return of(ScopeDenialReason.UNSUPPORTED_ROLE, null, callerUserId, detail, auditId);
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

    public UUID getRequestId() {
        return requestId;
    }

    public UUID getSessionId() {
        return sessionId;
    }

    public ForbiddenScopeException withCorrelation(
            final UUID correlatedRequestId,
            final UUID correlatedAuditId,
            final UUID correlatedSessionId) {
        return new ForbiddenScopeException(
                denialReason,
                patientId,
                callerUserId,
                getMessage(),
                correlatedRequestId,
                correlatedAuditId,
                correlatedSessionId);
    }
}
