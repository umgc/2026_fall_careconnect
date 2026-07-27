package com.careconnect.service.ai.safety;

import com.careconnect.dto.ai.AiCitation;

import java.util.List;
import java.util.UUID;

/**
 * Input to the Ask AI secondary safety gate.
 */
public record SafetyInput(
        String query,
        String draftAnswerText,
        List<AiCitation> citations,
        Long patientId,
        Long callerUserId,
        UUID sessionId,
        UUID auditId,
        UUID requestId,
        String sourceSurface,
        String locale,
        boolean groundingFailed,
        List<String> groundingFailureCodes
) {
}
