package com.careconnect.dto.ai;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Client snapshot of an Ask AI conversation to retain for linked-caregiver review.
 *
 * <p>When {@code caregiverUserId} is null, the conversation is shared with all active
 * linked caregivers for the patient.
 */
public record AiAskShareRequest(
        @NotNull Long patientId,
        UUID sessionId,
        Long caregiverUserId,
        @NotEmpty
        @Size(max = 100)
        @Valid
        List<AiAskShareMessage> messages) {

    public record AiAskShareMessage(
            @Size(max = 16) String role,
            @NotBlank @Size(max = 8000) String text,
            @Size(max = 64) String occurredAt) {
    }
}
