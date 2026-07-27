package com.careconnect.service.ai.safety;

import java.util.List;
import java.util.UUID;

/**
 * Result of {@link SafetyPipeline#process(SafetyInput)}.
 */
public record SafetyOutcome(
        SafetyDecision decision,
        int tier,
        List<String> triggerCodes,
        List<ValidationFinding> findings,
        String escalationLevel,
        UUID heldItemId
) {
    public static SafetyOutcome deliverTier1(
            final List<String> triggerCodes,
            final List<ValidationFinding> findings,
            final String escalationLevel) {
        return new SafetyOutcome(
                SafetyDecision.DELIVER_TIER1,
                1,
                List.copyOf(triggerCodes),
                List.copyOf(findings),
                escalationLevel,
                null);
    }

    public static SafetyOutcome holdTier2(
            final List<String> triggerCodes,
            final List<ValidationFinding> findings) {
        return new SafetyOutcome(
                SafetyDecision.HOLD_TIER2,
                2,
                List.copyOf(triggerCodes),
                List.copyOf(findings),
                "hitl_hold",
                null);
    }

    public static SafetyOutcome block(
            final List<String> triggerCodes,
            final List<ValidationFinding> findings) {
        return new SafetyOutcome(
                SafetyDecision.BLOCK,
                0,
                List.copyOf(triggerCodes),
                List.copyOf(findings),
                "blocked",
                null);
    }

    public SafetyOutcome withHeldItemId(final UUID heldItemId) {
        return new SafetyOutcome(
                decision, tier, triggerCodes, findings, escalationLevel, heldItemId);
    }
}
