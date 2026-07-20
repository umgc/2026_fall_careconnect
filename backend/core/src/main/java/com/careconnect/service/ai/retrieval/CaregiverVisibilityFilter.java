package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;

/**
 * Encodes how indexed rows with {@code caregiver_visibility} metadata may be retrieved
 * for the caller role (REQ-SC-8 / summary consent gates).
 */
public record CaregiverVisibilityFilter(Role callerRole, boolean consentGranted) {

    public boolean permits(String caregiverVisibility) {
        if (callerRole == Role.ADMIN || callerRole == Role.PATIENT) {
            return true;
        }
        if (caregiverVisibility == null || caregiverVisibility.isBlank()) {
            return true;
        }

        return switch (caregiverVisibility.toLowerCase()) {
            case "auto", "shared" -> true;
            case "on_consent" -> consentGranted;
            case "hidden", "patient_only" -> false;
            default -> callerRole != Role.FAMILY_MEMBER;
        };
    }
}
