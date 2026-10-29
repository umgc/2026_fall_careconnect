package com.careconnect.model.conditiondetection;

/**
 * One condition's result from an adapter.
 *
 * @param condition       the screened condition
 * @param severityLevel   0 = no indicator; higher is more severe (model-specific scale)
 * @param severityLabel   stable label for the level, e.g. {@code NONE}, {@code MILD}
 * @param rawScore        model-native score kept for audit, or {@code null}
 * @param evidenceSummary short de-identified rationale, or {@code null}
 */
public record ConditionFinding(
        ConditionName condition,
        int severityLevel,
        String severityLabel,
        Double rawScore,
        String evidenceSummary) {
}
