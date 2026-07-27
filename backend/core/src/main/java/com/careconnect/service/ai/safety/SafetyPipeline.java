package com.careconnect.service.ai.safety;

import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Secondary validation + tier classification for Ask AI (SCC-3 / REQ-SC-4).
 */
@Service
public class SafetyPipeline {

    private final TierClassifier tierClassifier;

    public SafetyPipeline(final TierClassifier tierClassifier) {
        this.tierClassifier = tierClassifier;
    }

    public SafetyOutcome process(final SafetyInput input) {
        if (input == null) {
            return SafetyOutcome.block(
                    List.of("INVALID_SAFETY_INPUT"),
                    List.of(new ValidationFinding(
                            ValidationFinding.Severity.CRITICAL,
                            "INVALID_SAFETY_INPUT",
                            "Safety input is required")));
        }

        final List<ValidationFinding> findings = new ArrayList<>();
        final String draft = input.draftAnswerText() == null ? "" : input.draftAnswerText().trim();

        if (input.groundingFailed() && draft.isEmpty()) {
            findings.add(new ValidationFinding(
                    ValidationFinding.Severity.CRITICAL,
                    "GROUNDING_FAILED",
                    "Answer could not be verified and no draft is available for review"));
            return SafetyOutcome.block(List.of("GROUNDING_FAILED"), findings);
        }

        if (draft.isEmpty() && !input.groundingFailed()) {
            findings.add(new ValidationFinding(
                    ValidationFinding.Severity.CRITICAL,
                    "EMPTY_DRAFT",
                    "Draft answer is empty"));
            return SafetyOutcome.block(List.of("EMPTY_DRAFT"), findings);
        }

        if (input.groundingFailed()) {
            findings.add(new ValidationFinding(
                    ValidationFinding.Severity.CRITICAL,
                    "UNSUPPORTED_CLAIM",
                    "Generated answer could not be verified against retrieved records"));
        }

        return tierClassifier.classify(input, findings);
    }
}
