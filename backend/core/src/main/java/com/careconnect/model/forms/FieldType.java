package com.careconnect.model.forms;

/**
 * Input control / data type for a {@link FormField}. Drives both frontend
 * rendering and backend value coercion. Mirrors the {@code fieldType} enum in
 * {@code forms/form-definition.schema.json}.
 */
public enum FieldType {
    TEXT,
    TEXTAREA,
    NUMBER,
    CURRENCY,
    DATE,
    EMAIL,
    PHONE,
    SSN,
    EIN,
    ZIP,
    STATE,
    ROUTING_NUMBER,
    ACCOUNT_NUMBER,
    CHECKBOX,
    BOOLEAN,
    RADIO,
    SELECT,
    MULTISELECT,
    SIGNATURE,
    /** Reference to an uploaded {@code UserFile} (e.g., voided check, lab result). */
    FILE_REF
}
