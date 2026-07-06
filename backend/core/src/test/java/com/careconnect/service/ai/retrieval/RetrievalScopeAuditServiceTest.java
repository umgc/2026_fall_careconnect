package com.careconnect.service.ai.retrieval;

import com.careconnect.model.User;
import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

class RetrievalScopeAuditServiceTest {

    private final RetrievalScopeAuditService auditService = new RetrievalScopeAuditService();

    @Test
    @DisplayName("logScopeDenied returns audit id and does not throw")
    void logScopeDeniedReturnsAuditId() {
        User caller = User.builder()
                .id(5L)
                .email("patient@test.com")
                .role(Role.PATIENT)
                .build();

        assertThatCode(() -> {
            var auditId = auditService.logScopeDenied(
                    caller,
                    42L,
                    ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                    "Patient 42 is out of scope");

            assertThat(auditId).isNotNull();
        }).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("logScopeDenied tolerates null caller")
    void logScopeDeniedToleratesNullCaller() {
        assertThat(auditService.logScopeDenied(
                null,
                99L,
                ScopeDenialReason.PATIENT_NOT_FOUND,
                "Patient 99 not found")).isNotNull();
    }
}
