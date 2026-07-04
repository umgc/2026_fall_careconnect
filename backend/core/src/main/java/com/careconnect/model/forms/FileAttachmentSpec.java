package com.careconnect.model.forms;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Declares how a completed submission integrates with existing
 * {@code UserFile} file-attachment records.
 * <p>
 * {@code category} MUST match a {@code UserFile.FileCategory} value so the
 * generated PDF and any supporting uploads are filed consistently with the
 * rest of the platform's documents.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class FileAttachmentSpec {
    /** UserFile.FileCategory name (e.g., ONBOARDING_FORM, HIRING_DOCUMENT). */
    private String category;
    /** When true, completing the form renders a PDF persisted as a UserFile. */
    private boolean generatesPdf;
    /** Categories of supporting evidence the employee may additionally upload. */
    private List<String> supportingDocumentCategories;
}
