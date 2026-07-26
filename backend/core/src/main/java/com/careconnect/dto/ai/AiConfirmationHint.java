package com.careconnect.dto.ai;

/**
 * Client hint to confirm answers with a care provider (REQ-SC-5/6 follow-up).
 */
public record AiConfirmationHint(
        boolean promptConfirmWithProvider,
        String message
) {
}
