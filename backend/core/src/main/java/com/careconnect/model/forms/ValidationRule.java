package com.careconnect.model.forms;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * A declarative validation rule attached to a {@link FormField}. The
 * {@code value} is loosely typed because its meaning depends on {@code type}
 * (e.g., an Integer for MIN_LENGTH, a List for ENUM).
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class ValidationRule {
    private ValidationRuleType type;
    private Object value;
    private String pattern;
    private String message;
}
