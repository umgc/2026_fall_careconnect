package com.careconnect.dto;

import java.util.ArrayList;
import java.util.List;

/**
 * Draft medication fields extracted from a label photo. When OCR or LLM
 * extraction fails the response still carries every field, blank, with status
 * MANUAL_ENTRY_REQUIRED so the client falls back to manual entry.
 */
public class MedicationPhotoExtractionResponse {

    public static final String STATUS_PREFILLED = "PREFILLED";
    public static final String STATUS_MANUAL_ENTRY_REQUIRED = "MANUAL_ENTRY_REQUIRED";

    public String status;
    public String message;
    public List<MedicationPhotoExtractedField> fields = new ArrayList<>();
}
