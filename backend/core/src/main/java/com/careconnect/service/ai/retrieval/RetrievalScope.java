package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;

import java.util.Set;

/**
 * Immutable RBAC scope resolved before hybrid Ask AI retrieval (FR-AI-1).
 */
public record RetrievalScope(
        Long callerUserId,
        Role callerRole,
        Set<Long> allowedPatientIds,
        Set<RetrievalRecordType> allowedSourceTypes,
        Set<RetrievalRecordType> excludedSourceTypes,
        CaregiverVisibilityFilter visibilityFilter,
        boolean consentGranted
) {
}
