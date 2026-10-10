package com.careconnect.dto;

/**
 * One medication field read from a label photo. Machine-generated values are
 * drafts for the user to review; blank values were not found on the label.
 */
public class MedicationPhotoExtractedField {

    public String key;
    public String label;
    public String value = "";

    /**
     * True when the value was prefilled by OCR + LLM rather than a person.
     */
    public boolean machineGenerated;

    public MedicationPhotoExtractedField() {
    }

    public MedicationPhotoExtractedField(String key, String label, String value, boolean machineGenerated) {
        this.key = key;
        this.label = label;
        this.value = value == null ? "" : value;
        this.machineGenerated = machineGenerated;
    }
}
