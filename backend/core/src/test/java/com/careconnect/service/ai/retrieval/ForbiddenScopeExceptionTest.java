package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class ForbiddenScopeExceptionTest {

    private static final UUID AUDIT_ID = UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");

    @Test
    @DisplayName("of includes patient id and caller email in message")
    void patientOutOfScopeMessage() {
        String detail = "Patient 42 is out of scope for user 'user@test.com'";
        ForbiddenScopeException ex = ForbiddenScopeException.of(
                ScopeDenialReason.PATIENT_OUT_OF_SCOPE, 42L, 10L, detail, AUDIT_ID);

        assertThat(ex.getMessage()).isEqualTo(detail);
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.PATIENT_OUT_OF_SCOPE);
        assertThat(ex.getErrorCode()).isEqualTo("FORBIDDEN_SCOPE");
        assertThat(ex.getAuditId()).isEqualTo(AUDIT_ID);
    }

    @Test
    @DisplayName("of includes patient id for not found")
    void patientNotFoundMessage() {
        String detail = "Patient 99 not found";
        ForbiddenScopeException ex = ForbiddenScopeException.of(
                ScopeDenialReason.PATIENT_NOT_FOUND, 99L, 10L, detail, AUDIT_ID);

        assertThat(ex.getMessage()).isEqualTo(detail);
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.PATIENT_NOT_FOUND);
    }

    @Test
    @DisplayName("of describes RBAC and consent filtering")
    void noPermittedSourceTypesMessage() {
        String detail = "No permitted source types remain for patient 7 after RBAC and consent filters";
        ForbiddenScopeException ex = ForbiddenScopeException.of(
                ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES, 7L, 10L, detail, AUDIT_ID);

        assertThat(ex.getMessage()).isEqualTo(detail);
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES);
    }

    @Test
    @DisplayName("unsupportedRole includes role name")
    void unsupportedRoleMessage() {
        String detail = "Role 'PATIENT' cannot resolve Ask AI retrieval scope";
        ForbiddenScopeException ex = ForbiddenScopeException.unsupportedRole(Role.PATIENT, 10L, detail, AUDIT_ID);

        assertThat(ex.getMessage()).isEqualTo(detail);
        assertThat(ex.getDenialReason()).isEqualTo(ScopeDenialReason.UNSUPPORTED_ROLE);
    }
}
