package com.careconnect.dto;

import com.careconnect.model.forms.FormType;
import lombok.Data;

import java.util.Map;

/**
 * Request payload for submitting a completed hiring/onboarding form.
 * <p>
 * {@link #fieldValues} are keyed by {@code "<sectionId>.<fieldId>"} to match the
 * structured schema and the server-side validator. {@link #confirmed} must be
 * {@code true}: the client sets it only after the user explicitly confirms the
 * submission, so an unconfirmed payload is rejected.
 */
@Data
public class FormSubmissionRequest {

    /** Which hiring/onboarding form this submission is for. */
    private FormType formType;

    /** Optional form version; defaults to the bundled/active definition. */
    private String version;

    /** Optional patient/subject context for the submission. */
    private Long patientId;

    /** Captured values keyed by "sectionId.fieldId". */
    private Map<String, Object> fieldValues;

    /** Must be true — the user confirmed the submission before sending. */
    private boolean confirmed;
}
