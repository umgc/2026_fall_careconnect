package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ForbiddenScopeExceptionTest {

    @Test
    @DisplayName("patientOutOfScope includes patient id and caller email")
    void patientOutOfScopeMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.patientOutOfScope(42L, "user@test.com");
        assertThat(ex.getMessage()).contains("42").contains("user@test.com");
    }

    @Test
    @DisplayName("patientNotFound includes patient id")
    void patientNotFoundMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.patientNotFound(99L);
        assertThat(ex.getMessage()).contains("99").contains("not found");
    }

    @Test
    @DisplayName("noPermittedSourceTypes describes RBAC and consent filtering")
    void noPermittedSourceTypesMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.noPermittedSourceTypes(7L);
        assertThat(ex.getMessage()).contains("7").contains("No permitted source types");
    }

    @Test
    @DisplayName("unsupportedRole includes role name")
    void unsupportedRoleMessage() {
        ForbiddenScopeException ex = ForbiddenScopeException.unsupportedRole(Role.PATIENT);
        assertThat(ex.getMessage()).contains("PATIENT");
    }
}
