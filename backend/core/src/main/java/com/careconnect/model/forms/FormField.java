package com.careconnect.model.forms;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * A single structured field within a {@link FormSection}: its data type,
 * required status, validation rules, choice options, and the mapping back to
 * the source document.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class FormField {
    /** Stable field key, unique within its section ([a-z0-9_]+). */
    private String id;
    private String label;
    private FieldType fieldType;
    private boolean required;
    private int order;
    private String helpText;
    private String placeholder;
    private Object defaultValue;
    @Builder.Default
    private boolean readOnly = false;
    /** Marks PII/PHI fields (e.g., SSN) for masking and audit logging. */
    @Builder.Default
    private boolean sensitive = false;
    /**
     * Optional role override when a single field is completed by a different
     * party than its section (e.g., a notary block inside an employee section).
     */
    private String completedBy;
    private List<FieldOption> options;
    private List<ValidationRule> validations;
    private SourceDocumentMapping sourceMapping;
    private FieldVisibilityCondition visibleWhen;
}
