package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class ForbiddenScopeExceptionTest {

    private static final UUID AUDIT_ID = UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");

    @Test
    @DisplayName("patientOutOfScope includes patient id and caller email")
    void patientOutOfScopeMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.patientOutOfScope(
                42L, "user@test.com", 10L, AUDIT_ID);

        assertThat(ex.getMessage()).contains("42").contains("user@test.com");
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.PATIENT_OUT_OF_SCOPE);
        assertThat(ex.getErrorCode()).isEqualTo("FORBIDDEN_SCOPE");
        assertThat(ex.getAuditId()).isEqualTo(AUDIT_ID);
    }

    @Test
    @DisplayName("patientNotFound includes patient id")
    void patientNotFoundMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.patientNotFound(99L, 10L, AUDIT_ID);

        assertThat(ex.getMessage()).contains("99").contains("not found");
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.PATIENT_NOT_FOUND);
    }

    @Test
    @DisplayName("noPermittedSourceTypes describes RBAC and consent filtering")
    void noPermittedSourceTypesMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.noPermittedSourceTypes(7L, 10L, AUDIT_ID);

        assertThat(ex.getMessage()).contains("7").contains("No permitted source types");
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES);
    }

    @Test
    @DisplayName("unsupportedRole includes role name")
    void unsupportedRoleMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.unsupportedRole(Role.PATIENT, 10L, AUDIT_ID);

        assertThat(ex.getMessage()).contains("PATIENT");
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.UNSUPPORTED_ROLE);
    }
}
