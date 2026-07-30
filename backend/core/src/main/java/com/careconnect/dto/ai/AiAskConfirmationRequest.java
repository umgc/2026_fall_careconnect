package com.careconnect.dto.ai;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

/**
 * REQ-SC-5/6 — caller confirmation decision for Ask AI delivery (Task 6.6).
 */
public record AiAskConfirmationRequest(
        @NotNull UUID sessionId,
        @NotNull Long patientId,
        UUID requestId,
        UUID auditId,
        @NotBlank String decision
) {
}
