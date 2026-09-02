package com.careconnect.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Map;

/**
 * Request payload for creating or updating a structured form entry captured
 * from an uploaded onboarding / intake document.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class StructuredEntryRequest {

    /**
     * Document type the fields were captured from. Optional on create — falls
     * back to the linked file's category when omitted.
     */
    private String documentType;

    /**
     * Patient context (care recipient). At least one context is required.
     */
    private Long patientId;

    /**
     * Employee context (caregiver / staff member). At least one context is required.
     */
    private Long employeeUserId;

    /**
     * Captured field values (field key -> value).
     */
    private Map<String, String> fields;

    // Manual accessors for Lombok compatibility
    public String getDocumentType() {
        return documentType;
    }

    public void setDocumentType(String documentType) {
        this.documentType = documentType;
    }

    public Long getPatientId() {
        return patientId;
    }

    public void setPatientId(Long patientId) {
        this.patientId = patientId;
    }

    public Long getEmployeeUserId() {
        return employeeUserId;
    }

    public void setEmployeeUserId(Long employeeUserId) {
        this.employeeUserId = employeeUserId;
    }

    public Map<String, String> getFields() {
        return fields;
    }

    public void setFields(Map<String, String> fields) {
        this.fields = fields;
    }
}
