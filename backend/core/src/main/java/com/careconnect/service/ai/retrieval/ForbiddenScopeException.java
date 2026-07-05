package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;

/**
 * Thrown when Ask AI retrieval scope cannot be granted for the caller and patient (FR-AI-1).
 * Maps to HTTP 403 with code {@code FORBIDDEN_SCOPE}.
 */
public class ForbiddenScopeException extends Exception {

    public ForbiddenScopeException(String message) {
        super(message);
    }

    public static ForbiddenScopeException patientOutOfScope(Long patientId, String callerEmail) {
        return new ForbiddenScopeException(
                String.format("Patient %d is out of scope for user '%s'", patientId, callerEmail));
    }

    public static ForbiddenScopeException patientNotFound(Long patientId) {
        return new ForbiddenScopeException(String.format("Patient %d not found", patientId));
    }

    public static ForbiddenScopeException noPermittedSourceTypes(Long patientId) {
        return new ForbiddenScopeException(
                String.format("No permitted source types remain for patient %d after RBAC and consent filters",
                        patientId));
    }

    public static ForbiddenScopeException unsupportedRole(Role callerRole) {
        return new ForbiddenScopeException(
                String.format("Role '%s' cannot resolve Ask AI retrieval scope", callerRole));
    }
}
