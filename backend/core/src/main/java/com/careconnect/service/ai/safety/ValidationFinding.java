package com.careconnect.service.ai.safety;

/**
 * A single secondary-validation finding.
 */
public record ValidationFinding(
        Severity severity,
        String code,
        String message
) {
    public enum Severity {
        INFO,
        WARN,
        CRITICAL
    }
}
