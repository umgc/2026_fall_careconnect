package com.careconnect.model.forms;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Maps a structured {@link FormField} back to its location on the original
 * paper source document, satisfying the requirement that each source document
 * is mapped to its corresponding structured fields.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class SourceDocumentMapping {
    /** Human label of the corresponding field on the source document. */
    private String documentField;
    /** Source section/step, e.g. "Step 1", "Section 1", "List A". */
    private String section;
    /** Line or box identifier, e.g. "1(a)", "Box 4". */
    private String line;
    /** 1-based page number on the source document. */
    private Integer page;
}
