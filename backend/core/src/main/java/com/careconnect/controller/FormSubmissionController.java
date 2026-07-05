package com.careconnect.controller;

import com.careconnect.dto.FormSubmissionRequest;
import com.careconnect.model.User;
import com.careconnect.model.UserFile;
import com.careconnect.model.forms.FormSubmission;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.FormSubmissionService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Endpoints for submitting completed hiring/onboarding forms to the database.
 * All routes require authentication (see SecurityConfig {@code /v1/api/**}).
 */
@RestController
@RequestMapping("/v1/api/forms")
@Slf4j
@Tag(name = "Hiring Forms", description = "Submit and review completed hiring/onboarding form data")
@SecurityRequirement(name = "Bearer Authentication")
public class FormSubmissionController {

    private final FormSubmissionService submissionService;
    private final UserRepository userRepository;
    private final CaregiverService caregiverService;

    public FormSubmissionController(FormSubmissionService submissionService,
                                    UserRepository userRepository,
                                    CaregiverService caregiverService) {
        this.submissionService = submissionService;
        this.userRepository = userRepository;
        this.caregiverService = caregiverService;
    }

    /**
     * Submit a completed form. The captured values are validated against the
     * form schema before anything is persisted; an unconfirmed or invalid
     * payload is rejected with no row written.
     */
    @PostMapping("/submissions")
    @Operation(summary = "Submit a completed hiring/onboarding form")
    public ResponseEntity<?> submit(@RequestBody FormSubmissionRequest request) {
        User user = getCurrentUser();
        if (!isHiringFormsUser(user)) {
            return forbidden();
        }

        if (request.getFormType() == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "formType is required"));
        }
        if (!request.isConfirmed()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "Submission must be confirmed before it can be saved"));
        }

        // IDOR guard: a caregiver may only file a submission against a patient
        // they have a care relationship with. A null patientId is a
        // self/onboarding submission and needs no relationship check.
        Long patientId = request.getPatientId();
        if (patientId != null && !canAccessPatient(user, patientId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to submit forms for this patient"));
        }

        UserFile.OwnerType ownerType = ownerTypeFor(user);
        try {
            FormSubmissionService.SubmissionResult result = submissionService.submit(
                    request.getFormType(),
                    request.getVersion(),
                    user.getId(),
                    ownerType,
                    request.getPatientId(),
                    request.getFieldValues());

            if (!result.isValid()) {
                return ResponseEntity.unprocessableEntity().body(Map.of(
                        "error", "Form has validation errors",
                        "details", result.errors()));
            }

            FormSubmission s = result.submission();
            return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                    "data", Map.of(
                            "id", s.getId(),
                            "formType", s.getFormType(),
                            "formVersion", s.getFormVersion(),
                            "status", s.getStatus(),
                            "submittedAt", s.getSubmittedAt()),
                    "message", "Form submitted successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            log.error("Failed to store form submission", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to store submission"));
        }
    }

    /** List the current user's own submissions (most recent first). */
    @GetMapping("/submissions/mine")
    @Operation(summary = "List my submitted hiring/onboarding forms")
    public ResponseEntity<?> mySubmissions() {
        User user = getCurrentUser();
        if (!isHiringFormsUser(user)) {
            return forbidden();
        }
        List<Map<String, Object>> data = submissionService
                .listForOwner(user.getId(), ownerTypeFor(user))
                .stream()
                .map(s -> {
                    Map<String, Object> m = new java.util.LinkedHashMap<>();
                    m.put("id", s.getId());
                    m.put("formType", s.getFormType());
                    m.put("formVersion", s.getFormVersion());
                    m.put("status", s.getStatus());
                    m.put("patientId", s.getPatientId());
                    m.put("submittedAt", s.getSubmittedAt());
                    m.put("createdAt", s.getCreatedAt());
                    return m;
                })
                .toList();
        return ResponseEntity.ok(Map.of("data", data));
    }

    /**
     * Hiring/onboarding forms are restricted to caregiver accounts, matching the
     * UI (the Hiring Forms tab is shown only to caregivers).
     */
    private boolean isHiringFormsUser(User user) {
        return user.getRole() == Role.CAREGIVER;
    }

    /**
     * True when the caregiver may file a submission against {@code patientId}.
     * Denies by default if the relationship lookup fails.
     */
    private boolean canAccessPatient(User user, Long patientId) {
        try {
            return caregiverService.hasAccessToPatient(user.getId(), patientId);
        } catch (Exception e) {
            log.warn("Patient access check failed for user {} / patient {}: {}",
                    user.getId(), patientId, e.getMessage());
            return false;
        }
    }

    private ResponseEntity<?> forbidden() {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", "Hiring forms are available to caregiver accounts only"));
    }

    private UserFile.OwnerType ownerTypeFor(User user) {
        try {
            return UserFile.OwnerType.valueOf(user.getRole().name());
        } catch (Exception e) {
            return UserFile.OwnerType.CAREGIVER;
        }
    }

    private User getCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String email = authentication.getName();
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("Current user not found: " + email));
    }
}
