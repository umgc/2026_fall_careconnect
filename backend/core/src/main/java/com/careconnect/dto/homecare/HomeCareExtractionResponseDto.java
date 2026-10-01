package com.careconnect.dto.homecare;

import java.util.ArrayList;
import java.util.List;

/**
 * Draft structured fields for a digitized home-care document, ready for human
 * review. When OCR or LLM extraction fails the response still carries the full
 * (empty) field schema with status MANUAL_ENTRY_REQUIRED so the client can
 * fall back cleanly to manual entry.
 */
public class HomeCareExtractionResponseDto {

    public static final String STATUS_PREFILLED = "PREFILLED";
    public static final String STATUS_MANUAL_ENTRY_REQUIRED = "MANUAL_ENTRY_REQUIRED";

    public String documentType;
    public String documentTypeDisplayName;
    public String status;
    public String message;

    /**
     * S3 key of the uploaded source document, when the upload succeeded.
     */
    public String documentLink;

    public List<ExtractedFieldDto> fields = new ArrayList<>();
}
