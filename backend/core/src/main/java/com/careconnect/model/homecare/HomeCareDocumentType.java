package com.careconnect.model.homecare;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Home-care onboarding document types that can be digitized through the
 * Textract + LLM pipeline. Each type carries its own field schema so that
 * extraction output is restricted to exactly the fields allowed for that
 * document type.
 *
 * The enum names intentionally match the frontend FileCategory values so a
 * confirmed digitized form can be stored under the matching category.
 */
public enum HomeCareDocumentType {

    EMPLOYMENT_APPLICATION("Employment Application", schema(
            "fullName", "Full Name",
            "phone", "Phone Number",
            "email", "Email Address",
            "address", "Home Address",
            "positionAppliedFor", "Position Applied For",
            "desiredStartDate", "Desired Start Date",
            "previousEmployer", "Most Recent Employer",
            "yearsOfExperience", "Years of Experience"
    )),

    CERTIFICATION("Certification / License", schema(
            "holderName", "Certificate Holder Name",
            "certificationType", "Certification / License Type",
            "certificationNumber", "Certification / License Number",
            "issuingOrganization", "Issuing Organization or State",
            "issueDate", "Issue Date",
            "expirationDate", "Expiration Date"
    )),

    TAX_FORM("Tax Form (W-4)", schema(
            "employeeName", "Employee Name",
            "address", "Home Address",
            "filingStatus", "Filing Status",
            "multipleJobs", "Multiple Jobs or Spouse Works",
            "dependentsAmount", "Claimed Dependents Amount",
            "otherIncome", "Other Income",
            "extraWithholding", "Extra Withholding"
    )),

    WORK_AUTHORIZATION("Work Authorization (I-9)", schema(
            "employeeName", "Employee Name",
            "dateOfBirth", "Date of Birth",
            "citizenshipStatus", "Citizenship / Immigration Status",
            "documentTitle", "Document Title",
            "documentNumber", "Document Number",
            "documentExpiration", "Document Expiration Date"
    ));

    private final String displayName;
    private final Map<String, String> fieldSchema;

    HomeCareDocumentType(String displayName, Map<String, String> fieldSchema) {
        this.displayName = displayName;
        this.fieldSchema = fieldSchema;
    }

    public String getDisplayName() {
        return displayName;
    }

    /**
     * Ordered map of allowed field key -> human readable label.
     */
    public Map<String, String> getFieldSchema() {
        return fieldSchema;
    }

    /**
     * JSON template with every allowed field blank, embedded in the LLM prompt
     * so the model returns exactly this shape.
     */
    public String promptSchemaJson() {
        StringBuilder sb = new StringBuilder("{\n");
        int i = 0;
        for (String key : fieldSchema.keySet()) {
            sb.append("  \"").append(key).append("\": \"\"");
            if (++i < fieldSchema.size()) {
                sb.append(',');
            }
            sb.append('\n');
        }
        return sb.append('}').toString();
    }

    public static Optional<HomeCareDocumentType> fromString(String value) {
        if (value == null || value.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(valueOf(value.trim().toUpperCase()));
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }

    private static Map<String, String> schema(String... keyLabelPairs) {
        Map<String, String> map = new LinkedHashMap<>();
        for (int i = 0; i < keyLabelPairs.length; i += 2) {
            map.put(keyLabelPairs[i], keyLabelPairs[i + 1]);
        }
        return java.util.Collections.unmodifiableMap(map);
    }
}
