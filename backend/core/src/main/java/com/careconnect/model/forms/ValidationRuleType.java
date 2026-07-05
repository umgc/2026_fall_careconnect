package com.careconnect.model.forms;

/**
 * Supported validation rule kinds for a {@link FormField}. Mirrors the
 * {@code validationRule.type} enum in {@code forms/form-definition.schema.json}.
 */
public enum ValidationRuleType {
    REQUIRED,
    MIN_LENGTH,
    MAX_LENGTH,
    PATTERN,
    MIN,
    MAX,
    EMAIL,
    SSN,
    EIN,
    ROUTING_NUMBER,
    DATE,
    DATE_RANGE,
    ENUM,
    CHECKED,
    AGE_MIN,
    CUSTOM
}
