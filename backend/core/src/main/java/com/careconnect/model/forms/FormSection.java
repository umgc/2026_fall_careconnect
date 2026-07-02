package com.careconnect.model.forms;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * A logical grouping of {@link FormField}s within a form, mirroring a section
 * or step of the source document (e.g., W-4 "Step 1", I-9 "Section 1").
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class FormSection {
    private String id;
    private String title;
    private String description;
    private int order;
    @Builder.Default
    private boolean required = true;
    /** True when the section may be completed multiple times (e.g., references). */
    @Builder.Default
    private boolean repeatable = false;
    /** Role responsible for completing the section: EMPLOYEE, EMPLOYER, etc. */
    private String completedBy;
    private List<FormField> fields;
}
