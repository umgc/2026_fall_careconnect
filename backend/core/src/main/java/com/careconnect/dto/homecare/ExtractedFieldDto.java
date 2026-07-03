package com.careconnect.dto.homecare;

/**
 * A single structured field produced by the home-care document digitization
 * pipeline. Machine-generated values are flagged so the UI can identify them,
 * and every field stays editable for human review.
 */
public class ExtractedFieldDto {

    public String key;
    public String label;
    public String value = "";

    /** True when the value was prefilled by OCR + LLM rather than a person. */
    public boolean machineGenerated;

    /** Prefilled values are drafts only; they always remain editable. */
    public boolean editable = true;

    public ExtractedFieldDto() {
    }

    public ExtractedFieldDto(String key, String label, String value, boolean machineGenerated) {
        this.key = key;
        this.label = label;
        this.value = value == null ? "" : value;
        this.machineGenerated = machineGenerated;
    }
}
